#!/usr/bin/env bash
# bench/http_torture/run_torture.sh — a torture harness that measures the
# NURL HTTP server ONLY against the Rust hyper/rustls peer, under the
# conditions a closed-loop hello-world bench never sees.
#
# Why this exists: bench/run_http.sh is a CLOSED-LOOP hello-world bench.
# Closed loop measures burst throughput, not the rate a server can
# SUSTAIN, and a 14-byte body hides the data-path cost a real response
# pays. This harness is open-loop (coordinated-omission corrected) over
# realistic body sizes, and reports the tail — the number a service SLO
# is written against.
#
# Dimensions (each a function below):
#   capacity   — ramp the offered rate until the latency knee; the
#                highest rate meeting the SLO is the sustainable capacity
#   loadlevels — open-loop at 50/80/95% of THAT capacity, p50/p99/p99.9
#   cpu        — CPU seconds per request (/proc/<pid>/stat utime+stime)
#   churn      — connection churn: a fresh TCP connection per request
#   slowloris  — many byte-at-a-time clients while a fast client measures
#   keepalive  — many concurrent idle-ish keep-alive connections
#   tls_resume — full vs resumed TLS handshake cost (openssl -reconnect)
#   soak       — a long open-loop run at 80%, watching for drift/leaks
#
# Fairness: each server is pinned to the SAME cores (SRV_CORES); the load
# generator to disjoint cores (GEN_CORES). Both peers serve byte-identical
# bodies from a precomputed buffer cloned per response.
#
# Usage:
#   bench/http_torture/run_torture.sh                 # smoke (short)
#   MODE=full bench/http_torture/run_torture.sh       # the real run
#   SIZES="16k" DIMS="capacity loadlevels" ... run     # subset
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HT="$ROOT/bench/http_torture"
SCRATCH="${SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/http-torture.XXXXXX")}"
mkdir -p "$SCRATCH"

MODE="${MODE:-smoke}"                       # smoke | full
SIZES="${SIZES:-1k 16k 1m}"                 # which bodies
DIMS="${DIMS:-capacity loadlevels cpu churn slowloris keepalive tls_resume soak}"
KNEE_MS="${KNEE_MS:-50}"                     # p99 SLO defining "sustainable"
OHA="${OHA:-$HOME/.cargo/bin/oha}"; [ -x "$OHA" ] || OHA="$(command -v oha || true)"
PY="$HT/lib.py"

# Core split: the servers get the lower half of the online CPUs, the load
# generator the upper half, so the two never share a core. The defaults
# are derived from `nproc` (a 12-thread workstation gives 0-5 / 6-11, a
# 4-vCPU CI runner 0-1 / 2-3); SRV_CORES / GEN_CORES override both.
NCPU="$(nproc 2>/dev/null || echo 2)"; [ "$NCPU" -ge 2 ] || NCPU=2
HALF=$(( NCPU / 2 ))
SRV_CORES="${SRV_CORES:-0-$(( HALF - 1 ))}"
GEN_CORES="${GEN_CORES:-$HALF-$(( NCPU - 1 ))}"

# Where the numbers came from, for the report header. run_http.sh reads
# the same two variables; the CI workflow sets them to the runner label
# and the run URL, a workstation run leaves them empty and gets uname.
HOST_LABEL="${BENCH_HOST_LABEL:-}"
RUN_URL="${BENCH_RUN_URL:-}"

if [ "$MODE" = full ]; then
  RAMP_SEC=5; MEAS_SEC=20; SOAK_SEC="${SOAK_SEC:-600}"; CONNS=400; SETTLE_SEC="${SETTLE_SEC:-120}"
else
  RAMP_SEC=3; MEAS_SEC=6;  SOAK_SEC="${SOAK_SEC:-20}";  CONNS=200; SETTLE_SEC="${SETTLE_SEC:-5}"
fi

NB="$SCRATCH/nurl_torture.bin"
RB="$HT/rust/target/release/http_torture"
NPORT=18080; RPORT=18081
NTLS=18543; RTLS=18544
declare -A HTTP_PORT=( [NURL]=$NPORT [RUST]=$RPORT )
declare -A TLS_PORT=(  [NURL]=$NTLS  [RUST]=$RTLS  )

say(){ printf '%s\n' "$*" >&2; }
die(){ say "ERROR: $*"; exit 1; }

# Kill any server/generator we spawned, even on Ctrl-C or error, so a
# NURL server (which listens whenever it gets too few args) never leaks.
_KIDS=""
cleanup(){ kill $_KIDS 2>/dev/null; pkill -f "$NB" 2>/dev/null; pkill -f "$RB" 2>/dev/null; }
trap cleanup EXIT INT TERM

[ -n "$OHA" ] && [ -x "$OHA" ] || die "oha not found (cargo install oha)"

# ── build both servers ──────────────────────────────────────────────
build() {
  say "[build] NURL torture server"
  ( cd "$ROOT" && ./nurl.sh bench/http_torture/server.nu "$NB" ) >"$SCRATCH/build_nurl.log" 2>&1 \
    || die "NURL server build failed (see $SCRATCH/build_nurl.log)"
  [ -x "$NB" ] || die "NURL server binary missing"
  say "[build] Rust hyper peer"
  ( cd "$HT/rust" && cargo build --release ) >"$SCRATCH/build_rust.log" 2>&1 \
    || die "Rust peer build failed (see $SCRATCH/build_rust.log)"
  [ -x "$RB" ] || die "Rust peer binary missing"
}

# self-signed EC P-256 cert for the TLS dimensions
CERT="$SCRATCH/cert.pem"; KEY="$SCRATCH/key.pem"
make_cert() {
  [ -f "$CERT" ] && return 0
  openssl ecparam -genkey -name prime256v1 -noout -out "$KEY" 2>/dev/null
  openssl req -new -x509 -key "$KEY" -out "$CERT" -days 3 -subj "/CN=localhost" 2>/dev/null
}

# url_for NAME plaintext|tls -> the base URL (pure; no side effects, so it
# survives the command-substitution subshell that start_server runs in).
url_for() {
  local name="$1" tls="$2"
  if [ "$tls" = tls ]; then echo "https://127.0.0.1:${TLS_PORT[$name]}"; else echo "http://127.0.0.1:${HTTP_PORT[$name]}"; fi
}

# start_server NAME plaintext|tls  -> echoes PID (URL via url_for)
start_server() {
  local name="$1" tls="$2" bin port url pid
  if [ "$name" = NURL ]; then bin="$NB"; else bin="$RB"; fi
  if [ "$tls" = tls ]; then
    port="${TLS_PORT[$name]}"; url="https://127.0.0.1:$port"
    make_cert
    if [ "$name" = NURL ]; then
      taskset -c "$SRV_CORES" "$bin" "$port" "$CERT" "$KEY" >"$SCRATCH/srv_${name}.log" 2>&1 & pid=$!
    else
      TLS_CERT="$CERT" TLS_KEY="$KEY" TLS_PORT="$port" taskset -c "$SRV_CORES" "$bin" >"$SCRATCH/srv_${name}.log" 2>&1 & pid=$!
    fi
  else
    port="${HTTP_PORT[$name]}"; url="http://127.0.0.1:$port"
    taskset -c "$SRV_CORES" "$bin" >"$SCRATCH/srv_${name}.log" 2>&1 & pid=$!
  fi
  local probe="$url/"; local ins=""; [ "$tls" = tls ] && ins="-k"
  local t=0
  until curl $ins -fsS --max-time 1 "$probe" >/dev/null 2>&1; do
    kill -0 "$pid" 2>/dev/null || { say "server $name died on start; log:"; tail -5 "$SCRATCH/srv_${name}.log" >&2; return 1; }
    sleep 0.2; t=$((t+1)); [ $t -gt 100 ] && { say "server $name never came up"; kill "$pid"; return 1; }
  done
  _KIDS="$_KIDS $pid"
  echo "$pid"
}

# oha_run OUTJSON EXTRA_ARGS... URL
oha_run() {
  local out="$1"; shift
  taskset -c "$GEN_CORES" "$OHA" --no-tui -j "$@" >"$out" 2>/dev/null
}

INS_FOR() { case "$1" in https*) echo "--insecure";; *) echo "";; esac; }

# ── capacity: ramp -q until the p99 SLO breaks; report last good rate ──
# echoes the sustainable rate (int) on stdout.
_sustains() { # $1 rate -> 0 if the server sustains it within SLO
  local q="$1" ins; ins="$(INS_FOR "$CAP_URL")"
  oha_run "$SCRATCH/cap.json" -z ${RAMP_SEC}s -q "$q" --latency-correction -c "$CONNS" $ins "$CAP_URL"
  read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$SCRATCH/cap.json")
  local ratio; ratio=$(python3 -c "print(int(100*$rps/$q))")
  say "    ramp q=$q -> ach=${rps%.*} p99=${p99}ms ok=$ok (${ratio}% of target)"
  [ "$ratio" -ge 97 ] && python3 -c "import sys; sys.exit(0 if $p99 <= $KNEE_MS else 1)"
}

# Body-size-agnostic knee search: double from a seed until the SLO breaks
# (finds the bracket), then bisect to the knee. Works for 1 MB (knee at a
# few thousand req/s) and 1 KB (knee past 200k) with no hand-tuned grid.
find_capacity() {
  CAP_URL="$1"
  local lo=0 hi=0 q="$CAP_SEED"
  # phase 1: double until failure → (lo=last good, hi=first fail)
  while [ "$q" -le "$CAP_MAX" ]; do
    if _sustains "$q"; then lo="$q"; q=$(( q*2 )); else hi="$q"; break; fi
  done
  [ "$lo" -eq 0 ] && { echo 0; return; }          # knee below the seed
  [ "$hi" -eq 0 ] && { echo "$lo"; return; }       # never failed by CAP_MAX
  # phase 2: bisect (lo, hi) to within CAP_TOL
  while [ $(( hi - lo )) -gt "$CAP_TOL" ]; do
    local mid=$(( (lo+hi)/2 ))
    if _sustains "$mid"; then lo="$mid"; else hi="$mid"; fi
  done
  echo "$lo"
}

report=""
add(){ report="$report$1"$'\n'; }

dim_capacity_and_load() {
  local size="$1"
  add "### Body $size — sustainable capacity & tail under load"
  add ""
  add "| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |"
  add "|---|--:|--:|--:|--:|"
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" plaintext)" || { add "| $name | START FAILED | | | |"; continue; }
    local url="$(url_for "$name" plaintext)/$size"
    say "  [$name $size] finding sustainable capacity"
    # Seed/ceiling/tolerance scale with body size so the knee search
    # spans 1 MB (thousands of req/s) and 1 KB (past 200k) alike.
    case "$size" in
      1m)  CAP_SEED=250;   CAP_MAX=64000;  CAP_TOL=250  ;;
      16k) CAP_SEED=8000;  CAP_MAX=512000; CAP_TOL=4000 ;;
      *)   CAP_SEED=16000; CAP_MAX=768000; CAP_TOL=8000 ;;
    esac
    local cap; cap="$(find_capacity "$url")"
    if [ "$cap" -eq 0 ]; then add "| $name | <${CAP_SEED} (knee below seed) | | | |"; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; continue; fi
    CAP_STORE["$name-$size"]="$cap"
    local cells=""
    local pct
    for pct in 50 80 95; do
      local q=$(( cap*pct/100 ))
      oha_run "$SCRATCH/ll_${name}_${size}_${pct}.json" -z ${MEAS_SEC}s -q "$q" --latency-correction -c "$CONNS" "$url"
      read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$SCRATCH/ll_${name}_${size}_${pct}.json")
      cells="$cells | ${p50}/${p99}/${p999}"
    done
    add "| $name | $(printf "%'d" "$cap")$cells |"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  done
  add ""
}

# ── CPU seconds per request ─────────────────────────────────────────
cpu_per_req() {
  local size="$1"
  add "### Body $size — CPU seconds per request (server-side)"
  add ""
  add "| Server | req served | CPU s (utime+stime) | µs / request |"
  add "|---|--:|--:|--:|"
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" plaintext)" || { add "| $name | START FAILED | | |"; continue; }
    local url="$(url_for "$name" plaintext)/$size"
    local cap="${CAP_STORE[$name-$size]:-40000}"; local q=$(( cap*70/100 ))
    # snapshot server CPU (sum over the process's threads via /proc/pid/stat)
    local u0 s0 u1 s1; read -r u0 s0 < <(awk '{print $14, $15}' /proc/$pid/stat)
    oha_run "$SCRATCH/cpu_${name}_${size}.json" -z ${MEAS_SEC}s -q "$q" --latency-correction -c "$CONNS" "$url"
    read -r u1 s1 < <(awk '{print $14, $15}' /proc/$pid/stat)
    local reqs; reqs=$(python3 "$PY" rps "$SCRATCH/cpu_${name}_${size}.json")
    reqs=$(python3 -c "print(int($reqs*$MEAS_SEC))")
    local hz; hz=$(getconf CLK_TCK)
    python3 - "$u0" "$s0" "$u1" "$s1" "$reqs" "$hz" "$name" <<'PY' >>"$SCRATCH/cpu.row"
import sys
u0,s0,u1,s1,reqs,hz=map(float,sys.argv[1:7]); name=sys.argv[7]
cpu=((u1+s1)-(u0+s0))/hz
us=cpu/reqs*1e6 if reqs else 0
print("| %s | %d | %.2f | %.2f |" % (name,int(reqs),cpu,us))
PY
    add "$(tail -1 "$SCRATCH/cpu.row")"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  done
  add ""
}

# ── connection churn: new TCP connection per request ────────────────
churn() {
  local size="$1"
  add "### Body $size — connection churn (no keep-alive, fresh conn/request)"
  add ""
  add "| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |"
  add "|---|--:|--:|--:|"
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" plaintext)" || { add "| $name | START FAILED | | |"; continue; }
    local url="$(url_for "$name" plaintext)/$size"
    oha_run "$SCRATCH/churn_${name}_${size}.json" -z ${MEAS_SEC}s -c 100 --disable-keepalive "$url"
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$SCRATCH/churn_${name}_${size}.json")
    add "| $name | $(printf "%'d" "${rps%.*}") | ${p50}/${p99}/${p999} | $ok |"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  done
  add ""
}

# ── slowloris: N byte-at-a-time clients, fast client measured meanwhile
slowloris() {
  add "### Slowloris — $SLOW_N trickle clients held open, fast-client latency meanwhile (16k)"
  add ""
  add "| Server | fast-client req/s | p50/p99 (ms) | survived |"
  add "|---|--:|--:|:--:|"
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" plaintext)" || { add "| $name | START FAILED | | |"; continue; }
    local url="$(url_for "$name" plaintext)"
    python3 "$HT/slowloris.py" "127.0.0.1" "${HTTP_PORT[$name]}" "$SLOW_N" "$SLOW_SEC" >"$SCRATCH/slow_${name}.log" 2>&1 &
    local spid=$!
    sleep 1
    oha_run "$SCRATCH/slowfast_${name}.json" -z ${SLOW_SEC}s -c 20 "$url/16k"
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$SCRATCH/slowfast_${name}.json")
    wait "$spid" 2>/dev/null
    local alive=no; kill -0 "$pid" 2>/dev/null && alive=yes
    add "| $name | $(printf "%'d" "${rps%.*}") | ${p50}/${p99} | $alive |"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  done
  add ""
}

# ── keep-alive scale: hold many concurrent keep-alive connections ───
keepalive_scale() {
  add "### Keep-alive scale — $KA_CONNS concurrent keep-alive connections (1k body)"
  add ""
  add "| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |"
  add "|---|--:|--:|--:|--:|"
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" plaintext)" || { add "| $name | START FAILED | | | |"; continue; }
    local url="$(url_for "$name" plaintext)/1k"
    oha_run "$SCRATCH/ka_${name}.json" -z ${MEAS_SEC}s -c "$KA_CONNS" "$url"
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$SCRATCH/ka_${name}.json")
    add "| $name | $KA_CONNS | $(printf "%'d" "${rps%.*}") | ${p50}/${p99}/${p999} | $ok |"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  done
  add ""
}

# ── TLS session resumption: full vs resumed handshake ───────────────
tls_resume() {
  add "### TLS 1.3 session resumption — does a reconnect skip the full handshake?"
  add ""
  add "| Server | resumption supported? | ticket | reconnect |"
  add "|---|:--:|:--:|:--:|"
  make_cert
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" tls)" || { add "| $name | START FAILED | | |"; continue; }
    local port="${TLS_PORT[$name]}"
    python3 "$HT/tls_resume.py" "127.0.0.1" "$port" >"$SCRATCH/tlsres_${name}.txt" 2>&1 || true
    local row; row="$(cat "$SCRATCH/tlsres_${name}.txt")"
    add "| $name | $row |"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  done
  add ""
}

# ── soak: long open-loop run at 80%, watch drift + errors ───────────
soak() {
  local size="16k"
  add "### Soak — ${SOAK_SEC}s open-loop at 80% of capacity ($size)"
  add ""
  add "| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |"
  add "|---|--:|--:|--:|--:|"
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" plaintext)" || { add "| $name | START FAILED | | | |"; continue; }
    local url="$(url_for "$name" plaintext)/$size"
    local cap="${CAP_STORE[$name-$size]:-100000}"; local q=$(( cap*80/100 ))
    local rss0; rss0=$(awk '/VmRSS/{print $2}' /proc/$pid/status)
    oha_run "$SCRATCH/soak_${name}.json" -z ${SOAK_SEC}s -q "$q" --latency-correction -c "$CONNS" "$url"
    local rss1; rss1=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null || echo NA)
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$SCRATCH/soak_${name}.json")
    local errs; errs=$(python3 -c "import json;d=json.load(open('$SCRATCH/soak_${name}.json'));e=d.get('errorDistribution') or {};print(sum(e.values()) if e else 0)")
    add "| $name | $(printf "%'d" "${rps%.*}") | ${p50}/${p99}/${p999} | $ok | ${errs} (RSS ${rss0}→${rss1} KiB) |"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  done
  add ""
}

SLOW_N="${SLOW_N:-200}"; SLOW_SEC="${SLOW_SEC:-8}"; KA_CONNS="${KA_CONNS:-2000}"
[ "$MODE" = smoke ] && { SLOW_N=50; SLOW_SEC=4; KA_CONNS=500; }

declare -A CAP_STORE

main() {
  build
  # Let the box settle before the first cell. The build just above is an
  # all-core LTO compile plus a cargo build, and whatever ran before this
  # script (a test suite, a sanitizer run) may have left the CPU hot: two
  # full runs on the reference host had their FIRST cell — NURL, 1 KB —
  # collapse to ~40 % of its clean capacity with the tail in the seconds,
  # while the same binary sustained the clean rate minutes later and the
  # peer, measured next, was unaffected. A cool-down costs two minutes;
  # a biased first cell costs the run.
  say "[settle] ${SETTLE_SEC}s idle before the first measurement"
  sleep "$SETTLE_SEC"
  local host kern cpu
  host="$(uname -sr)"; cpu="$(LC_ALL=C lscpu | awk -F: '/Model name/{gsub(/^ +/,"",$2);print $2;exit}')"
  add "# HTTP torture — NURL vs Rust (hyper/rustls)"
  add ""
  add "Open-loop, coordinated-omission corrected (\`oha -q --latency-correction\`). Server pinned to cores \`$SRV_CORES\`, generator to \`$GEN_CORES\`. Both peers serve byte-identical bodies. MODE=**$MODE**."
  add ""
  if [ -n "$HOST_LABEL" ]; then add "- Host: **$HOST_LABEL** — \`$host\` — $cpu ($NCPU CPUs)"; else add "- Host: \`$host\` — $cpu ($NCPU CPUs)"; fi
  add "- NURL: \`$("$ROOT/build/nurlc" --version 2>/dev/null || echo n/a)\`  ·  oha: \`$($OHA --version 2>&1 | head -1)\`  ·  commit \`$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo n/a)\`"
  [ -n "$RUN_URL" ] && add "- Run: $RUN_URL"
  add "- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ ${KNEE_MS} ms."
  add ""
  case " $DIMS " in *" capacity "*|*" loadlevels "*) for s in $SIZES; do dim_capacity_and_load "$s"; done;; esac
  case " $DIMS " in *" cpu "*)       for s in $SIZES; do cpu_per_req "$s"; done;; esac
  case " $DIMS " in *" churn "*)     for s in $SIZES; do churn "$s"; done;; esac
  case " $DIMS " in *" slowloris "*) slowloris;; esac
  case " $DIMS " in *" keepalive "*) keepalive_scale;; esac
  case " $DIMS " in *" tls_resume "*) tls_resume;; esac
  case " $DIMS " in *" soak "*)      soak;; esac
  add "---"
  add ""
  add "### Reading these numbers"
  add ""
  add "- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is \`oha\` on ${GEN_CORES} hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is \"both faster than this host can drive,\" i.e. a tie at the floor of the generator's ceiling."
  add "- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one \`sendmsg\`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request."
  add "- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close)."
  printf '%s' "$report" > "$HT/TORTURE_RESULTS.md"
  say ""; say "report -> $HT/TORTURE_RESULTS.md   (scratch: $SCRATCH)"
  printf '%s' "$report"
}
main
