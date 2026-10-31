#!/usr/bin/env bash
# bench/tls_bench/run_tls.sh — the TLS benchmark: NURL against Rust
# (rustls on aws-lc-rs) on every cost a TLS 1.3 HTTP stack pays, measured
# so the report can say which one to work on.
#
# Sections (DIMS, each a function below):
#   prims      the crypto primitives a handshake and a record are made of,
#              single core, ns/op (prims.nu vs tls_prims)
#   handshake  full and resumed handshakes per second at saturation, per
#              group (X25519, P-256, X25519MLKEM768) and certificate (ECDSA
#              P-256, RSA-2048), with SERVER CPU per handshake — the number
#              that splits into "the crypto" (from prims) and "the rest"
#   latency    the same handshakes one at a time: unloaded latency
#   records    small keep-alive requests over TLS and over plaintext — the
#              per-request cost of the record layer
#   bulk       one connection downloading 1 MB bodies: MB/s and server CPU
#              per byte, per cipher suite, plaintext baseline, and NURL with
#              kTLS (NURL_KTLS=1)
#   client     NURL's packages/http-client against reqwest, both against
#              the same (Rust) server: new connection with and without
#              resumption, keep-alive, 1 MB bodies
#
# Servers: NURL is the packages/http HttpApp facade in http_app_async mode
# (bench/http_torture/server.nu — the surface a NURL service deploys); Rust
# is hyper 1.x on tokio with tokio-rustls (rust/src/bin/tls_server.rs).
# The load generator (tls_load) is the same thin tokio-rustls client for
# both; it pins the group and suite it measures, so neither server's
# preference order decides a row.
#
# Cores: the server gets SRV_CORES (default: the lowest quarter of the
# online CPUs, at least one — core 0 on a 4-vCPU runner), the generator
# the rest. A TLS client costs about as much per handshake as the server,
# so the generator needs the larger share to keep a server saturated;
# every saturation cell also records the server's CPU utilisation, and
# the report flags any cell where the server was not the bottleneck.
#
# Writes this run's report to $MD_OUT (default: the scratch directory).
# With STORE=1 (the tls-bench workflow) the run also becomes its CPU
# family's latest — bench/tls_bench/runs/<family>.tsv — and the committed
# reports are re-rendered: TLS_RESULTS.<family>.md per family and the
# index TLS_RESULTS.md. The family comes from the CPU's vendor and flags
# (gen_tls_results.py), because the runner pool's families disagree about
# the ratios (Agora #112); a workstation run is posted in its PR, not
# committed.
#
# Usage:
#   bench/tls_bench/run_tls.sh                    # smoke (~3 min, checks the pipeline)
#   MODE=full bench/tls_bench/run_tls.sh          # the real run (~10 min of measurement)
#   DIMS="handshake bulk" MODE=full bench/tls_bench/run_tls.sh
#   STORE=1 MODE=full bench/tls_bench/run_tls.sh  # and record it for its CPU family
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TB="$ROOT/bench/tls_bench"
SCRATCH="${SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/tls-bench.XXXXXX")}"
mkdir -p "$SCRATCH" "$ROOT/bench/_build"
MD_OUT="${MD_OUT:-$SCRATCH/TLS_RESULTS.md}"
STORE="${STORE:-0}"

MODE="${MODE:-smoke}"
DIMS="${DIMS:-prims handshake latency records bulk client}"
if [ "$MODE" = full ]; then
  HS_SEC=15; LAT_SEC=5; KA_SEC=10; CLI_SEC=6; PRIM_RUNS=3; SETTLE_SEC="${SETTLE_SEC:-60}"
else
  HS_SEC=3;  LAT_SEC=2; KA_SEC=3;  CLI_SEC=2; PRIM_RUNS=1; SETTLE_SEC="${SETTLE_SEC:-0}"
fi
HS_CONNS="${HS_CONNS:-64}"     # concurrent handshakes at saturation
KA_CONNS="${KA_CONNS:-64}"     # keep-alive connections in the records rows

NCPU="$(nproc 2>/dev/null || echo 2)"; [ "$NCPU" -ge 2 ] || NCPU=2
NSRV=$(( NCPU / 4 )); [ "$NSRV" -ge 1 ] || NSRV=1
SRV_CORES="${SRV_CORES:-0-$(( NSRV - 1 ))}"
GEN_CORES="${GEN_CORES:-$NSRV-$(( NCPU - 1 ))}"
PRIM_CORE="${PRIM_CORE:-${SRV_CORES%%[-,]*}}"
# How many cores SRV_CORES names (for the utilisation column).
SRV_NCORES="$(python3 -c "
n=0
for p in '$SRV_CORES'.split(','):
    a,_,b=p.partition('-'); n+=int(b or a)-int(a)+1
print(n)")"

NB="$ROOT/bench/_build/tls_nurl_server"
NP="$ROOT/bench/_build/tls_prims"
NC="$ROOT/bench/_build/tls_client"
RT="$TB/rust/target/release"
NPORT=18543; NPLAIN=18080      # server.nu: TLS on the given port, plaintext on 18080
RPORT=18544; RPLAIN=18081
RES="$SCRATCH/results.tsv"; : > "$RES"

say(){ printf '%s\n' "$*" >&2; }
die(){ say "ERROR: $*"; exit 1; }
_KIDS=""
cleanup(){ kill $_KIDS 2>/dev/null; pkill -f "$NB" 2>/dev/null; pkill -f "$RT/tls_server" 2>/dev/null; }
trap cleanup EXIT INT TERM

# ── build ───────────────────────────────────────────────────────────
build() {
  say "[build] NURL server, primitives, client"
  ( cd "$ROOT" && ./nurl.sh -O2 bench/http_torture/server.nu "$NB" ) >"$SCRATCH/build_nurl.log" 2>&1 || die "NURL server build failed ($SCRATCH/build_nurl.log)"
  ( cd "$ROOT" && ./nurl.sh -O2 bench/tls_bench/prims.nu "$NP" ) >>"$SCRATCH/build_nurl.log" 2>&1 || die "NURL prims build failed ($SCRATCH/build_nurl.log)"
  ( cd "$ROOT" && ./nurl.sh -O2 bench/tls_bench/client.nu "$NC" ) >>"$SCRATCH/build_nurl.log" 2>&1 || die "NURL client build failed ($SCRATCH/build_nurl.log)"
  say "[build] Rust server, load generator, primitives, client"
  cargo build --release --manifest-path "$TB/rust/Cargo.toml" >"$SCRATCH/build_rust.log" 2>&1 || die "Rust build failed ($SCRATCH/build_rust.log)"
}

# One P-256 and one RSA-2048 identity, self-signed for localhost.
certs() {
  openssl ecparam -genkey -name prime256v1 -noout -out "$SCRATCH/ec.key" 2>/dev/null
  openssl req -new -x509 -key "$SCRATCH/ec.key" -out "$SCRATCH/ec.crt" -days 3 -subj /CN=localhost 2>/dev/null
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$SCRATCH/rsa.key" 2>/dev/null
  openssl req -new -x509 -key "$SCRATCH/rsa.key" -out "$SCRATCH/rsa.crt" -days 3 -subj /CN=localhost 2>/dev/null
  [ -s "$SCRATCH/ec.crt" ] && [ -s "$SCRATCH/rsa.crt" ] || die "openssl could not make the test certificates"
}

# The vendor and the crypto-relevant CPU flags present, in a fixed order:
# every flag a NURL or aws-lc kernel is chosen by (bench/cpu_env.py, shared
# with the other runner-measured reports).
cpu_vendor() { python3 "$ROOT/bench/cpu_env.py" vendor; }
cpu_flags() { python3 "$ROOT/bench/cpu_env.py" flags; }

# ── servers ─────────────────────────────────────────────────────────
# start IMPL CERT(ec|rsa|plain) → echoes the PID once the server answers.
# Extra environment for the NURL server (NURL_KTLS=1) comes from SRV_ENV.
start() {
  local impl="$1" cert="$2" pid url
  if [ "$impl" = NURL ]; then
    if [ "$cert" = plain ]; then
      env ${SRV_ENV:-} taskset -c "$SRV_CORES" "$NB" >"$SCRATCH/srv_NURL.log" 2>&1 & pid=$!
      url="http://127.0.0.1:$NPLAIN/"
    else
      env ${SRV_ENV:-} taskset -c "$SRV_CORES" "$NB" "$NPORT" "$SCRATCH/$cert.crt" "$SCRATCH/$cert.key" >"$SCRATCH/srv_NURL.log" 2>&1 & pid=$!
      url="https://127.0.0.1:$NPORT/"
    fi
  else
    if [ "$cert" = plain ]; then
      taskset -c "$SRV_CORES" "$RT/tls_server" "$RPLAIN" >"$SCRATCH/srv_RUST.log" 2>&1 & pid=$!
      url="http://127.0.0.1:$RPLAIN/"
    else
      taskset -c "$SRV_CORES" "$RT/tls_server" "$RPORT" "$SCRATCH/$cert.crt" "$SCRATCH/$cert.key" >"$SCRATCH/srv_RUST.log" 2>&1 & pid=$!
      url="https://127.0.0.1:$RPORT/"
    fi
  fi
  local t=0
  until curl -k -fsS --http1.1 --max-time 5 "$url" >/dev/null 2>&1; do
    kill -0 "$pid" 2>/dev/null || { say "$impl server died on start:"; tail -5 "$SCRATCH/srv_$impl.log" >&2; return 1; }
    sleep 0.2; t=$((t+1)); [ $t -gt 100 ] && { say "$impl server never came up"; kill "$pid"; return 1; }
  done
  _KIDS="$_KIDS $pid"
  echo "$pid"
}
stop() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }
tls_port()   { [ "$1" = NURL ] && echo $NPORT  || echo $RPORT; }
plain_port() { [ "$1" = NURL ] && echo $NPLAIN || echo $RPLAIN; }

cpu_ticks() { awk '{print $14 + $15}' "/proc/$1/stat" 2>/dev/null || echo 0; }
ktls_tx()   { awk '/^TlsTxSw/{print $2}' /proc/net/tls_stat 2>/dev/null || echo 0; }
HZ="$(getconf CLK_TCK)"

# measure SECTION CASE IMPL PID -- tls_load args...
# Runs the generator, brackets it with the server's CPU ticks and the
# kernel's kTLS counter, and appends one result line.
measure() {
  local sec="$1" case="$2" impl="$3" pid="$4"; shift 5
  local c0 c1 k0 k1 out
  c0="$(cpu_ticks "$pid")"; k0="$(ktls_tx)"
  out="$(taskset -c "$GEN_CORES" "$RT/tls_load" "$@" 2>>"$SCRATCH/load.err")"
  c1="$(cpu_ticks "$pid")"; k1="$(ktls_tx)"
  local cpu_ns=$(( (c1 - c0) * 1000000000 / HZ ))
  printf 'M\t%s\t%s\t%s\t%s srv_cpu_ns=%s srv_cores=%s ktls_tx=%s\n' "$sec" "$case" "$impl" "$out" "$cpu_ns" "$SRV_NCORES" "$(( ${k1:-0} - ${k0:-0} ))" >>"$RES"
  say "    $sec/$case/$impl: ${out%% hs_p50*}"
}

# ── prims ───────────────────────────────────────────────────────────
dim_prims() {
  say "[prims] $PRIM_RUNS run(s) per implementation on core $PRIM_CORE"
  local i
  for i in $(seq 1 "$PRIM_RUNS"); do
    taskset -c "$PRIM_CORE" "$NP" "$SCRATCH/rsa.key" | awk -F'\t' '$1=="ROW"{print "P\tNURL\t"$2"\t"$3}' >>"$RES"
    taskset -c "$PRIM_CORE" "$RT/tls_prims"          | awk -F'\t' '$1=="ROW"{print "P\tRUST\t"$2"\t"$3}' >>"$RES"
  done
}

# ── handshakes ──────────────────────────────────────────────────────
# case: cert group resume
HS_CASES="ec:x25519:0 ec:x25519:1 ec:p256:0 ec:mlkem:0 rsa:x25519:0"

dim_handshake() {
  local conns="$1" secs="$2" sec="$3" spec impl
  for spec in $HS_CASES; do
    IFS=: read -r cert group resume <<<"$spec"
    for impl in NURL RUST; do
      local pid; pid="$(start "$impl" "$cert")" || { printf 'M\t%s\t%s\t%s\tfailed=1\n' "$sec" "$spec" "$impl" >>"$RES"; continue; }
      measure "$sec" "$spec" "$impl" "$pid" -- --addr "127.0.0.1:$(tls_port "$impl")" --mode hs --conns "$conns" --secs "$secs" --group "$group" --suite aes128 --resume "$resume"
      stop "$pid"
    done
  done
}

# ── small keep-alive requests ───────────────────────────────────────
dim_records() {
  local impl
  for impl in NURL RUST; do
    local pid
    pid="$(start "$impl" ec)" && {
      measure records "tls:/1k" "$impl" "$pid" -- --addr "127.0.0.1:$(tls_port "$impl")" --mode ka --conns "$KA_CONNS" --secs "$KA_SEC" --path /1k --group x25519 --suite aes128
      stop "$pid"; }
    pid="$(start "$impl" plain)" && {
      measure records "plain:/1k" "$impl" "$pid" -- --addr "127.0.0.1:$(plain_port "$impl")" --mode ka --conns "$KA_CONNS" --secs "$KA_SEC" --path /1k --plain 1
      stop "$pid"; }
  done
}

# ── bulk ────────────────────────────────────────────────────────────
dim_bulk() {
  local impl suite
  for impl in NURL RUST; do
    local pid
    for suite in aes128 chacha; do
      pid="$(start "$impl" ec)" && {
        measure bulk "$suite" "$impl" "$pid" -- --addr "127.0.0.1:$(tls_port "$impl")" --mode ka --conns 1 --secs "$KA_SEC" --path /1m --group x25519 --suite "$suite"
        stop "$pid"; }
    done
    pid="$(start "$impl" plain)" && {
      measure bulk plain "$impl" "$pid" -- --addr "127.0.0.1:$(plain_port "$impl")" --mode ka --conns 1 --secs "$KA_SEC" --path /1m --plain 1
      stop "$pid"; }
  done
  # NURL with the record layer handed to the kernel. Whether it actually
  # engaged is the ktls_tx column (the kernel's TlsTxSw counter).
  local pid
  pid="$(SRV_ENV=NURL_KTLS=1 start NURL ec)" && {
    measure bulk "aes128+ktls" NURL "$pid" -- --addr "127.0.0.1:$NPORT" --mode ka --conns 1 --secs "$KA_SEC" --path /1m --group x25519 --suite aes128
    stop "$pid"; }
}

# ── client ──────────────────────────────────────────────────────────
dim_client() {
  local pid; pid="$(start RUST ec)" || return
  local mode path
  for spec in full:/ resume:/ ka:/1k ka:/1m; do
    IFS=: read -r mode path <<<"$spec"
    local url="https://localhost:$RPORT$path"
    local o
    o="$(taskset -c "${GEN_CORES%%[-,]*}" "$NC" "$mode" "$url" "$CLI_SEC" 2>>"$SCRATCH/client.err")"
    printf 'M\tclient\t%s\tNURL\t%s\n' "$spec" "$o" >>"$RES"; say "    client/$spec/NURL: $o"
    o="$(taskset -c "${GEN_CORES%%[-,]*}" "$RT/tls_client" "$mode" "$url" "$CLI_SEC" 2>>"$SCRATCH/client.err")"
    printf 'M\tclient\t%s\tRUST\t%s\n' "$spec" "$o" >>"$RES"; say "    client/$spec/RUST: $o"
  done
  stop "$pid"
}

main() {
  command -v cargo >/dev/null || die "cargo not found"
  command -v openssl >/dev/null || die "openssl not found"
  build
  certs
  say "[settle] ${SETTLE_SEC}s idle before the first measurement"
  sleep "$SETTLE_SEC"
  # Short-lived connections by the hundred thousand: keep the generator
  # out of ephemeral-port exhaustion (best effort; CI runs as a sudoer).
  sudo -n sysctl -q -w net.ipv4.ip_local_port_range="1024 65000" net.ipv4.tcp_tw_reuse=1 2>/dev/null || true

  {
    printf 'ENV\tnow\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'ENV\thost\t%s\n' "${BENCH_HOST_LABEL:-$(uname -s) $(uname -m)}"
    printf 'ENV\tkernel\t%s\n' "$(uname -srm)"
    printf 'ENV\tcpu\t%s\n' "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //')"
    # What decides the CPU family and every kernel choice: the vendor and
    # the crypto-relevant flags present (x86 `flags`, AArch64 `Features`),
    # NURL's own CPU answers and per-primitive kernels (prims --tiers),
    # and any masking of either side's CPUID.
    printf 'ENV\tcpu_vendor\t%s\n' "$(cpu_vendor)"
    printf 'ENV\tcpu_flags\t%s\n' "$(cpu_flags)"
    printf 'ENV\tnurl_cpu_mask\t%s\n' "$(env | grep -E '^NURL_CPU_[A-Z0-9]+=' | sort | tr '\n' ' ' | sed 's/ $//' | grep . || echo none)"
    printf 'ENV\topenssl_ia32cap\t%s\n' "${OPENSSL_ia32cap:-unset}"
    printf 'ENV\tcores\t%s\n' "$NCPU"
    printf 'ENV\tsrv_cores\t%s\n' "$SRV_CORES"
    printf 'ENV\tgen_cores\t%s\n' "$GEN_CORES"
    printf 'ENV\tcommit\t%s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    printf 'ENV\trun_url\t%s\n' "${BENCH_RUN_URL:-}"
    printf 'ENV\tnurl\t%s\n' "$("$ROOT/build/nurlc" --version 2>/dev/null | head -1)"
    printf 'ENV\trust\t%s\n' "$(rustc --version 2>/dev/null)"
    printf 'ENV\tmode\t%s\n' "$MODE"
    printf 'ENV\tsecs\ths=%s lat=%s ka=%s client=%s prim_runs=%s\n' "$HS_SEC" "$LAT_SEC" "$KA_SEC" "$CLI_SEC" "$PRIM_RUNS"
    local c
    for c in rustls aws-lc-rs hyper tokio reqwest; do
      printf 'ENV\tcrate_%s\t%s\n' "$c" "$(grep -A1 "^name = \"$c\"$" "$TB/rust/Cargo.lock" 2>/dev/null | sed -n 's/^version = "\(.*\)"/\1/p' | head -1)"
    done
  } >>"$RES"
  "$NP" --tiers >>"$RES" || die "prims --tiers failed"

  case " $DIMS " in *" prims "*)     dim_prims;; esac
  case " $DIMS " in *" handshake "*) say "[handshake] saturation, $HS_CONNS conns, ${HS_SEC}s"; dim_handshake "$HS_CONNS" "$HS_SEC" handshake;; esac
  case " $DIMS " in *" latency "*)   say "[latency] one at a time, ${LAT_SEC}s"; dim_handshake 1 "$LAT_SEC" latency;; esac
  case " $DIMS " in *" records "*)   say "[records] $KA_CONNS keep-alive conns, ${KA_SEC}s"; dim_records;; esac
  case " $DIMS " in *" bulk "*)      say "[bulk] one connection, 1 MB bodies, ${KA_SEC}s"; dim_bulk;; esac
  case " $DIMS " in *" client "*)    say "[client] http-client vs reqwest, ${CLI_SEC}s"; dim_client;; esac

  python3 "$TB/gen_tls_results.py" <"$RES" >"$MD_OUT" || die "report generation failed (raw results: $RES)"
  say ""; say "report -> $MD_OUT   (raw: $RES)"
  if [ "$STORE" = 1 ]; then
    local fam; fam="$(python3 "$TB/gen_tls_results.py" --store "$TB" <"$RES")" || die "recording the run failed (raw results: $RES)"
    say "recorded for its CPU family -> $fam (index: $TB/TLS_RESULTS.md)"
  fi
}
main
