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
#   loadlevels — open-loop at 50/80/95% of THAT capacity, p50/p99/p99.9,
#                and the server's CPU per request at each level; the 80 %
#                cell of 1k and 16k runs TAIL_RUNS times (median [min–max])
#   churn      — connection churn: a fresh TCP connection per request
#   slowloris  — many byte-at-a-time clients while a fast client measures
#   keepalive  — many concurrent idle-ish keep-alive connections
#   tls_resume — full vs resumed TLS handshake cost (openssl -reconnect)
#   soak       — one long open-loop run at 80%, sampled every SOAK_EVERY s
#                for RSS, CPU, steal and open fds
# (`cpu` is accepted as an alias of `loadlevels` for one release: the CPU
# per request is now measured inside the load levels, Agora #120.)
#
# Every oha run is a cell, and every cell reports why it looks the way it
# does, not only what it measured (lib.py): its errors split into harness
# artefacts and server-attributable ones, † when the VM's steal passed
# 2 % of the window, ‡ when the generator used ≥ 90 % of its cores.
#
# Fairness: each server is pinned to the SAME cores (SRV_CORES); the load
# generator to disjoint cores (GEN_CORES). Both peers serve byte-identical
# bodies from a precomputed buffer cloned per response. Which server goes
# first alternates per body size, so a box that is still warming up does
# not bias the same server everywhere.
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
DIMS="${DIMS:-capacity loadlevels churn slowloris keepalive tls_resume soak}"
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
GEN_NCORES="$(python3 "$PY" ncores "$GEN_CORES")"

# Where the numbers came from, for the report header. run_http.sh reads
# the same two variables; the CI workflow sets them to the runner label
# and the run URL, a workstation run leaves them empty and gets uname.
HOST_LABEL="${BENCH_HOST_LABEL:-}"
RUN_URL="${BENCH_RUN_URL:-}"

if [ "$MODE" = full ]; then
  RAMP_SEC=5; MEAS_SEC=20; SOAK_SEC="${SOAK_SEC:-600}"; CONNS=400; SETTLE_SEC="${SETTLE_SEC:-120}"
  TAIL_RUNS="${TAIL_RUNS:-3}"; SOAK_EVERY="${SOAK_EVERY:-10}"
else
  RAMP_SEC=3; MEAS_SEC=6;  SOAK_SEC="${SOAK_SEC:-20}";  CONNS=200; SETTLE_SEC="${SETTLE_SEC:-5}"
  TAIL_RUNS="${TAIL_RUNS:-3}"; SOAK_EVERY="${SOAK_EVERY:-2}"
fi

NB="$SCRATCH/nurl_torture.bin"
RB="$HT/rust/target/release/http_torture"
NPORT=18080; RPORT=18081
NTLS=18543; RTLS=18544
declare -A HTTP_PORT=( [NURL]=$NPORT [RUST]=$RPORT )
declare -A TLS_PORT=(  [NURL]=$NTLS  [RUST]=$RTLS  )
HZ="$(getconf CLK_TCK)"
CELLS="$SCRATCH/cells.tsv"; : >"$CELLS"   # cell<TAB>server<TAB>oha json, for the error/env sections

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

stop_server(){ kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }

# oha_run OUTJSON EXTRA_ARGS... URL
# Besides oha's JSON, leaves OUTJSON.env: the aggregate /proc/stat line
# before and after (steal, iowait), the wall time, and the generator's own
# CPU time — `times` in the subshell that ran it reports its children's,
# and taskset execs oha, so that is oha's (lib.py env_of).
oha_run() {
  local out="$1"; shift
  local st0 st1 t0 t1 tm
  st0="$(head -1 /proc/stat)"; t0="$(date +%s%N)"
  tm="$( { taskset -c "$GEN_CORES" "$OHA" --no-tui -j "$@" >"$out" 2>/dev/null; times; } | tail -1 )"
  t1="$(date +%s%N)"; st1="$(head -1 /proc/stat)"
  printf 'stat0=%s\nstat1=%s\nwall_ns=%s\ngen_times=%s\ngen_cores=%s\n' \
    "$st0" "$st1" "$(( t1 - t0 ))" "$tm" "$GEN_NCORES" >"$out.env"
}

# reg CELL SERVER JSON — the run goes into the errors-by-type and
# environment sections at the end.
reg(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$CELLS"; }

# The server's CPU so far, utime+stime in clock ticks (all its threads).
ticks_of(){ awk '{print $14 + $15}' "/proc/$1/stat"; }

# Which server goes first for the i-th body size: alternating, so the
# first cell after a settle (the one a still-warm box biases) is not the
# same server's every time.
order_for(){ if [ $(( $1 % 2 )) -eq 0 ]; then echo "NURL RUST"; else echo "RUST NURL"; fi; }

INS_FOR() { case "$1" in https*) echo "--insecure";; *) echo "";; esac; }

# ── capacity: ramp -q until the p99 SLO breaks; report last good rate ──
# echoes the sustainable rate (int) on stdout. Each ramp's JSON is kept as
# $CAP_TAG.<rate>.json, so the cells that bound the knee can be marked.
_sustains() { # $1 rate -> 0 if the server sustains it within SLO
  local q="$1" ins j; ins="$(INS_FOR "$CAP_URL")"; j="$SCRATCH/$CAP_TAG.$q.json"
  oha_run "$j" -z ${RAMP_SEC}s -q "$q" --latency-correction -c "$CONNS" $ins "$CAP_URL"
  reg "$CAP_CELL" "$CAP_NAME" "$j"
  read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$j")
  local ratio; ratio=$(python3 -c "print(int(100*$rps/$q))")
  say "    ramp q=$q -> ach=${rps%.*} p99=${p99}ms ok=$ok (${ratio}% of target)"
  [ "$ratio" -ge 97 ] && python3 -c "import sys; sys.exit(0 if $p99 <= $KNEE_MS else 1)"
}

# Body-size-agnostic knee search: double from a seed until the SLO breaks
# (finds the bracket), then bisect to the knee. Works for 1 MB (knee at a
# few thousand req/s) and 1 KB (knee past 200k) with no hand-tuned grid.
# Leaves the bracket in CAP_LO / CAP_HI (CAP_HI 0: never failed).
find_capacity() {
  CAP_URL="$1"
  local lo=0 hi=0 q="$CAP_SEED"
  # phase 1: double until failure → (lo=last good, hi=first fail)
  while [ "$q" -le "$CAP_MAX" ]; do
    if _sustains "$q"; then lo="$q"; q=$(( q*2 )); else hi="$q"; break; fi
  done
  if [ "$lo" -ne 0 ] && [ "$hi" -ne 0 ]; then
    # phase 2: bisect (lo, hi) to within CAP_TOL
    while [ $(( hi - lo )) -gt "$CAP_TOL" ]; do
      local mid=$(( (lo+hi)/2 ))
      if _sustains "$mid"; then lo="$mid"; else hi="$mid"; fi
    done
  fi
  CAP_LO="$lo"; CAP_HI="$hi"
}

report=""
add(){ report="$report$1"$'\n'; }

declare -A ROW
# emit_rows: the table rows in a fixed order (NURL, RUST) whichever ran first.
emit_rows(){ local n; for n in NURL RUST; do [ -n "${ROW[$n]:-}" ] && add "${ROW[$n]}"; done; ROW=(); }

# One load level of one server: oha runs (one, or TAIL_RUNS for the 80 %
# tail of 1k/16k) with the server's CPU sampled around them. Sets LL_CELL
# (the table cell), LL_CPU (µs/request) and LL_JSONS.
load_level() {
  local name="$1" size="$2" pct="$3" pid="$4" url="$5" q="$6" runs="$7"
  local k t0 t1 j jsons=()
  t0="$(ticks_of "$pid")"
  for (( k = 1; k <= runs; k++ )); do
    j="$SCRATCH/ll_${name}_${size}_${pct}_$k.json"
    oha_run "$j" -z ${MEAS_SEC}s -q "$q" --latency-correction -c "$CONNS" "$url"
    reg "$size load $pct%" "$name" "$j"
    jsons+=("$j")
  done
  t1="$(ticks_of "$pid")"
  LL_CPU="$(python3 "$PY" cpu_us "$t0" "$t1" "$HZ" "${jsons[@]}")"
  local m; m="$(python3 "$PY" marks "${jsons[@]}")"
  if [ "$runs" -gt 1 ]; then
    local p99 p999 p50
    IFS=$'\t' read -r p99 p999 < <(python3 "$PY" spread "${jsons[@]}")
    p50="$(for j in "${jsons[@]}"; do python3 "$PY" row "$j" | awk '{print $3}'; done | sort -g | awk '{v[NR]=$1} END {print v[int((NR+1)/2)]}')"
    LL_CELL="${p50} / ${p99} / ${p999}${m:+ $m}"
  else
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "${jsons[0]}")
    LL_CELL="${p50}/${p99}/${p999}${m:+ $m}"
  fi
  LL_JSONS=("${jsons[@]}")
}

dim_capacity_and_load() {
  local size="$1" idx="$2" order; order="$(order_for "$idx")"
  local runs80=1; case "$size" in 1k|16k) runs80="$TAIL_RUNS";; esac
  add "### Body $size — sustainable capacity & tail under load"
  add ""
  [ "$runs80" -gt 1 ] && add "The 80 % cell is $runs80 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: ${order%% *}." \
                      || add "Measured first: ${order%% *}."
  add ""
  add "| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |"
  add "|---|--:|--:|--:|--:|--:|--:|"
  local name
  for name in $order; do
    local pid; pid="$(start_server "$name" plaintext)" || { ROW[$name]="| $name | START FAILED | | | | | |"; continue; }
    local url="$(url_for "$name" plaintext)/$size"
    say "  [$name $size] finding sustainable capacity"
    # Seed/ceiling/tolerance scale with body size so the knee search
    # spans 1 MB (thousands of req/s) and 1 KB (past 200k) alike.
    case "$size" in
      1m)  CAP_SEED=250;   CAP_MAX=64000;  CAP_TOL=250  ;;
      16k) CAP_SEED=8000;  CAP_MAX=512000; CAP_TOL=4000 ;;
      *)   CAP_SEED=16000; CAP_MAX=768000; CAP_TOL=8000 ;;
    esac
    CAP_TAG="cap_${name}_${size}"; CAP_CELL="$size capacity search"; CAP_NAME="$name"
    find_capacity "$url"
    local cap="$CAP_LO"
    if [ "$cap" -eq 0 ]; then ROW[$name]="| $name | <${CAP_SEED} (knee below seed) | | | | | |"; stop_server "$pid"; continue; fi
    CAP_STORE["$name-$size"]="$cap"
    # The knee's two sides are what the capacity cell stands on: a mark on
    # either (the generator saturated, or the VM stalled) qualifies it.
    local knee=("$SCRATCH/$CAP_TAG.$CAP_LO.json"); [ "$CAP_HI" -ne 0 ] && knee+=("$SCRATCH/$CAP_TAG.$CAP_HI.json")
    local cm; cm="$(python3 "$PY" marks "${knee[@]}")"
    local cells="" cpus="" all=() pct
    for pct in 50 80 95; do
      local runs=1; [ "$pct" = 80 ] && runs="$runs80"
      load_level "$name" "$size" "$pct" "$pid" "$url" $(( cap*pct/100 )) "$runs"
      cells="$cells | $LL_CELL"; cpus="${cpus:+$cpus / }$LL_CPU"; all+=("${LL_JSONS[@]}")
    done
    ROW[$name]="| $name | $(printf "%'d" "$cap")${cm:+ $cm}$cells | $cpus | $(python3 "$PY" errcell "${all[@]}") |"
    stop_server "$pid"
  done
  emit_rows
  add ""
}

# ── connection churn: new TCP connection per request ────────────────
churn() {
  local size="$1" idx="$2" order; order="$(order_for "$idx")"
  add "### Body $size — connection churn (no keep-alive, fresh conn/request)"
  add ""
  add "| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |"
  add "|---|--:|--:|--:|--:|"
  local name
  for name in $order; do
    local pid; pid="$(start_server "$name" plaintext)" || { ROW[$name]="| $name | START FAILED | | | |"; continue; }
    local url="$(url_for "$name" plaintext)/$size" j="$SCRATCH/churn_${name}_${size}.json"
    oha_run "$j" -z ${MEAS_SEC}s -c 100 --disable-keepalive "$url"
    reg "$size churn" "$name" "$j"
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$j")
    local m; m="$(python3 "$PY" marks "$j")"
    ROW[$name]="| $name | $(printf "%'d" "${rps%.*}")${m:+ $m} | ${p50}/${p99}/${p999} | $ok | $(python3 "$PY" errcell "$j") |"
    stop_server "$pid"
  done
  emit_rows
  add ""
}

# ── slowloris: N byte-at-a-time clients, fast client measured meanwhile
slowloris() {
  add "### Slowloris — $SLOW_N trickle clients held open, fast-client latency meanwhile (16k)"
  add ""
  add "| Server | fast-client req/s | p50/p99 (ms) | survived | errors |"
  add "|---|--:|--:|:--:|--:|"
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" plaintext)" || { ROW[$name]="| $name | START FAILED | | | |"; continue; }
    local url="$(url_for "$name" plaintext)" j="$SCRATCH/slowfast_${name}.json"
    python3 "$HT/slowloris.py" "127.0.0.1" "${HTTP_PORT[$name]}" "$SLOW_N" "$SLOW_SEC" >"$SCRATCH/slow_${name}.log" 2>&1 &
    local spid=$!
    sleep 1
    oha_run "$j" -z ${SLOW_SEC}s -c 20 "$url/16k"
    reg "slowloris" "$name" "$j"
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$j")
    wait "$spid" 2>/dev/null
    local alive=no; kill -0 "$pid" 2>/dev/null && alive=yes
    local m; m="$(python3 "$PY" marks "$j")"
    ROW[$name]="| $name | $(printf "%'d" "${rps%.*}")${m:+ $m} | ${p50}/${p99} | $alive | $(python3 "$PY" errcell "$j") |"
    stop_server "$pid"
  done
  emit_rows
  add ""
}

# ── keep-alive scale: hold many concurrent keep-alive connections ───
keepalive_scale() {
  add "### Keep-alive scale — $KA_CONNS concurrent keep-alive connections (1k body)"
  add ""
  add "| Server | conns | req/s | p50/p99/p99.9 (ms) | ok | errors |"
  add "|---|--:|--:|--:|--:|--:|"
  local name
  for name in RUST NURL; do
    local pid; pid="$(start_server "$name" plaintext)" || { ROW[$name]="| $name | START FAILED | | | | |"; continue; }
    local url="$(url_for "$name" plaintext)/1k" j="$SCRATCH/ka_${name}.json"
    oha_run "$j" -z ${MEAS_SEC}s -c "$KA_CONNS" "$url"
    reg "keep-alive scale" "$name" "$j"
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$j")
    local m; m="$(python3 "$PY" marks "$j")"
    ROW[$name]="| $name | $KA_CONNS | $(printf "%'d" "${rps%.*}")${m:+ $m} | ${p50}/${p99}/${p999} | $ok | $(python3 "$PY" errcell "$j") |"
    stop_server "$pid"
  done
  emit_rows
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
    stop_server "$pid"
  done
  add ""
}

# ── soak: one long open-loop run at 80%, sampled for drift ──────────
# The oha run stays ONE continuous run (connection lifetimes as before);
# beside it, every SOAK_EVERY s: the server's RSS, its CPU ticks, the
# /proc/stat total and steal, and its open fds.
soak_sampler() { # PID OUT
  local pid="$1" out="$2" t0="$SECONDS" rss ticks total steal fds
  while kill -0 "$pid" 2>/dev/null; do
    rss="$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null)" || break
    ticks="$(ticks_of "$pid" 2>/dev/null)" || break
    read -r total steal < <(head -1 /proc/stat | awk '{t = 0; for (i = 2; i <= 9; i++) t += $i; print t, $9}')
    fds="$(ls "/proc/$pid/fd" 2>/dev/null | wc -l)"
    [ -n "$rss" ] && [ -n "$ticks" ] && echo "$(( SECONDS - t0 )) $rss $ticks $total $steal $fds" >>"$out"
    sleep "$SOAK_EVERY"
  done
}

soak() {
  local size="16k"
  add "### Soak — ${SOAK_SEC}s open-loop at 80% of capacity ($size), sampled every ${SOAK_EVERY}s"
  add ""
  add "| Server | req/s | p50/p99/p99.9 (ms) | ok | errors | RSS KiB start→end (max) | RSS KiB/min | CPU % of a core | open fds start→end (max) | steal > 2 % |"
  add "|---|--:|--:|--:|--:|--:|--:|--:|--:|---|"
  local name
  for name in NURL RUST; do
    local pid; pid="$(start_server "$name" plaintext)" || { ROW[$name]="| $name | START FAILED | | | | | | | | |"; continue; }
    local url="$(url_for "$name" plaintext)/$size" j="$SCRATCH/soak_${name}.json" smp="$SCRATCH/soak_${name}.samples"
    local cap="${CAP_STORE[$name-$size]:-100000}"; local q=$(( cap*80/100 ))
    : >"$smp"
    soak_sampler "$pid" "$smp" & local sp=$!
    oha_run "$j" -z ${SOAK_SEC}s -q "$q" --latency-correction -c "$CONNS" "$url"
    sleep 0.2; kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null
    # one closing sample, so the window ends where oha did
    echo "$(( $(awk 'END{print $1}' "$smp" 2>/dev/null || echo 0) + 1 )) $(awk '/VmRSS/{print $2}' "/proc/$pid/status") $(ticks_of "$pid") $(head -1 /proc/stat | awk '{t = 0; for (i = 2; i <= 9; i++) t += $i; print t, $9}') $(ls "/proc/$pid/fd" | wc -l)" >>"$smp"
    reg "soak" "$name" "$j"
    read -r rps ok p50 p99 p999 < <(python3 "$PY" row "$j")
    local m; m="$(python3 "$PY" marks "$j")"
    local drift; drift="$(python3 "$PY" soak "$smp" "$HZ" | tr '\t' '|' | sed 's/|/ | /g')"
    ROW[$name]="| $name | $(printf "%'d" "${rps%.*}")${m:+ $m} | ${p50}/${p99}/${p999} | $ok | $(python3 "$PY" errcell "$j") | $drift |"
    stop_server "$pid"
  done
  emit_rows
  add ""
}

SLOW_N="${SLOW_N:-200}"; SLOW_SEC="${SLOW_SEC:-8}"; KA_CONNS="${KA_CONNS:-2000}"
[ "$MODE" = smoke ] && { SLOW_N=50; SLOW_SEC=4; KA_CONNS=500; }

declare -A CAP_STORE
declare -A WALL
WALL_ORDER=""
# timed NAME CMD... — runs one dimension and keeps its wall time.
timed(){ local name="$1" t0="$SECONDS"; shift; "$@"; WALL[$name]=$(( ${WALL[$name]:-0} + SECONDS - t0 )); case " $WALL_ORDER " in *" $name "*) ;; *) WALL_ORDER="$WALL_ORDER $name";; esac; }

main() {
  local T0="$SECONDS"
  timed build build
  # Let the box settle before the first cell. The build just above is an
  # all-core LTO compile plus a cargo build, and whatever ran before this
  # script (a test suite, a sanitizer run) may have left the CPU hot: two
  # full runs on the reference host had their FIRST cell — NURL, 1 KB —
  # collapse to ~40 % of its clean capacity with the tail in the seconds,
  # while the same binary sustained the clean rate minutes later and the
  # peer, measured next, was unaffected. A cool-down costs two minutes;
  # a biased first cell costs the run. (Which server goes first now
  # alternates per body size, which removes the systematic part.)
  say "[settle] ${SETTLE_SEC}s idle before the first measurement"
  timed settle sleep "$SETTLE_SEC"
  # `cpu` was its own dimension; it is measured inside the load levels now.
  case " $DIMS " in *" cpu "*) say "[dims] 'cpu' is an alias of 'loadlevels' (CPU per request is measured at every load level)"; DIMS="$DIMS loadlevels";; esac
  local host cpu fam flags rustc_v
  host="$(uname -sr)"; cpu="$(LC_ALL=C lscpu | awk -F: '/Model name/{gsub(/^ +/,"",$2);print $2;exit}')"
  fam="$(python3 "$ROOT/bench/cpu_env.py" family)"; flags="$(python3 "$ROOT/bench/cpu_env.py" flags)"
  rustc_v="$(rustc --version 2>/dev/null | awk '{print $2}')"
  local lock="$HT/rust/Cargo.lock" crates
  crates="$(for c in hyper rustls tokio; do awk -v c="$c" '$0 == "name = \"" c "\"" {getline; gsub(/version = |"/, ""); print c " " $0; exit}' "$lock"; done | paste -sd, - | sed 's/,/, /g')"
  local idx s
  idx=0; case " $DIMS " in *" capacity "*|*" loadlevels "*) for s in $SIZES; do timed loadlevels dim_capacity_and_load "$s" "$idx"; idx=$(( idx + 1 )); done;; esac
  idx=1; case " $DIMS " in *" churn "*)     for s in $SIZES; do timed churn churn "$s" "$idx"; idx=$(( idx + 1 )); done;; esac
  case " $DIMS " in *" slowloris "*) timed slowloris slowloris;; esac
  case " $DIMS " in *" keepalive "*) timed keepalive keepalive_scale;; esac
  case " $DIMS " in *" tls_resume "*) timed tls_resume tls_resume;; esac
  case " $DIMS " in *" soak "*)      timed soak soak;; esac
  local body="$report"; report=""
  add "# HTTP torture — NURL vs Rust (hyper/rustls)"
  add ""
  add "Open-loop, coordinated-omission corrected (\`oha -q --latency-correction\`). Server pinned to cores \`$SRV_CORES\`, generator to \`$GEN_CORES\`. Both peers serve byte-identical bodies. MODE=**$MODE**."
  add ""
  if [ -n "$HOST_LABEL" ]; then add "- Host: **$HOST_LABEL** — \`$host\` — $cpu ($NCPU CPUs)"; else add "- Host: \`$host\` — $cpu ($NCPU CPUs)"; fi
  add "- CPU family \`$fam\` (bench/cpu_env.py) — flags: \`${flags:-none}\`"
  add "- NURL: \`$("$ROOT/build/nurlc" --version 2>/dev/null || echo n/a)\`  ·  Rust peer: rustc \`${rustc_v:-n/a}\`, $crates  ·  oha: \`$($OHA --version 2>&1 | head -1)\`  ·  commit \`$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo n/a)\`"
  [ -n "$RUN_URL" ] && add "- Run: $RUN_URL"
  add "- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ ${KNEE_MS} ms."
  local steal_max gen_bound; read -r steal_max gen_bound < <(python3 "$PY" thresholds)
  add "- **†** the VM's steal passed $steal_max % of the cell's window (a stall coordinated-omission correction charges to the server being measured). **‡** the generator used ≥ $gen_bound % of its cores (\`$GEN_CORES\`): the rate is oha's ceiling, not the server's. On a capacity cell a mark means the run at the knee carried it. **errors**: server-attributable count and its commonest type, then the harness artefacts in brackets — the full list is under *Errors by type*."
  add ""
  report="$report$body"
  add "---"
  add ""
  add "$(python3 "$PY" errsection "$CELLS")"
  add ""
  add "### Environment per cell (max over the cell's runs, % of the window)"
  add ""
  add "| Cell | Server | steal | iowait | generator CPU |"
  add "|---|---|--:|--:|--:|"
  local cell name js
  while IFS=$'\t' read -r cell name; do
    js="$(awk -F'\t' -v c="$cell" -v n="$name" '$1 == c && $2 == n {print $3}' "$CELLS" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    add "| $cell | $name | $(python3 "$PY" envnote $js) |"
  done < <(awk -F'\t' '!seen[$1 FS $2]++ {print $1 "\t" $2}' "$CELLS")
  add ""
  add "### Wall time per dimension"
  add ""
  add "| Dimension | wall |"
  add "|---|--:|"
  local d
  for d in $WALL_ORDER; do add "| $d | $(( WALL[$d] / 60 )) min $(( WALL[$d] % 60 )) s |"; done
  local total=$(( SECONDS - T0 ))
  add "| **all** | **$(( total / 60 )) min $(( total % 60 )) s** |"
  add ""
  add "### Reading these numbers"
  add ""
  add "- **A ‡ on a 1 KB capacity is the generator's ceiling, not the server's.** When both servers report a ‡ capacity, that is \`oha\` on ${GEN_CORES} hitting its own generation limit — the honest conclusion is \"both faster than this host can drive\"."
  add "- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request column makes it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one \`sendmsg\`; a response can borrow a caller-owned body)."
  add "- **A tail claim needs the spread.** The 80 % cell of 1 KB and 16 KB is several runs; a difference inside their [min–max] ranges is not a difference."
  add "- **Read the soak's drift, not its tail.** A † names a stall the VM's host caused, which coordinated-omission correction back-charges to the server being measured. The RSS slope and the fd counts are the server-specific signal (bounded per-connection buffers, freed at connection close)."
  printf '%s' "$report" > "$HT/TORTURE_RESULTS.md"
  say ""; say "report -> $HT/TORTURE_RESULTS.md   (scratch: $SCRATCH)"
  printf '%s' "$report"
}
main
