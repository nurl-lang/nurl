#!/usr/bin/env bash
# ============================================================
#  unikernel/tests/swarm_gate.sh — plan B10's endpoint milestone, gated.
#
#  The SAME swarm-mcp package that runs hosted boots as a unikernel
#  guest, --connects OUT to a relay on the host over the pure TCP
#  stack and virtio-net, appears in the census, and completes both
#  kernel flavours end-to-end:
#
#    expr   sum of x*x over [0,1000) = 332833500 — no wasm involved,
#           so this half isolates boot + relay + census + dispatch.
#    wasm   the coordinator compiles `@ kernel i x → i { ^ * x x }`
#           to wasm32-wasi and the GUEST runs the chunks IN-PROCESS
#           on the pure-NURL nwasm — a guest has no processes to
#           run an external runtime with, which is what the
#           in-process engine exists for. sum over [0,100) = 328350.
#
#  It also MEASURES cold-start → first completed answer, the number
#  the plan's exit criterion names. Under TCG that is an interpreter
#  floor, not a ceiling — the figure is reported, not asserted.
#
#  The wasm half needs a wasm toolchain (wasmbuilder resolves $NURLC,
#  then $NURL_ZIG → $NURL_HOME/zig/zig → zig on PATH). Without one it
#  says SKIP loudly and the expr half still gates. The build-API
#  fallback is pointed at a closed port on purpose: a gate that could
#  quietly compile over the network would be measuring the network.
#
#  Usage: swarm_gate.sh     (QEMU / QEMU_ARGS honoured via run_qemu.sh)
# ============================================================
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
say() { echo "swarm_gate: $*"; }

command -v curl >/dev/null 2>&1 || { say "SKIP: no curl"; exit 0; }
command -v "${QEMU:-qemu-system-x86_64}" >/dev/null 2>&1 \
    || { say "SKIP: ${QEMU:-qemu-system-x86_64} not found (set QEMU like run_qemu.sh)"; exit 0; }

RELAY_PORT=18994
MCP_PORT=18995
TOKEN="swarm-gate-$$"
OUTDIR="${NURL_UNIKERNEL_OUT:-$ROOT/build/unikernel}"
mkdir -p "$OUTDIR"

# The coordinator compiles wasm kernels LOCALLY through wasmbuilder;
# aim it at this repo's compiler, and make the network fallback
# impossible rather than merely unlikely.
export NURLC="${NURLC:-$ROOT/build/nurlc}"
export NURL_STDLIB="${NURL_STDLIB:-$ROOT}"
export NURL_BUILD_API="http://127.0.0.1:1"

# ── materialise the package's path dependencies ─────────────────
# `packages/*/deps/` is gitignored — it is a BUILD ARTEFACT that
# nurlpkg materialises from the manifest, so a fresh checkout (CI's)
# has none while a developer's tree does. This gate is the first thing
# in compiler CI to build a package, and it silently built against a
# developer-only artefact until CI said "did not build". Do what a
# package consumer does: every `name = { path = … }` in the manifest
# becomes deps/name. Derived from the manifest, not a hardcoded list,
# so a new dependency cannot quietly break this again.
PKG="$ROOT/packages/swarm-mcp"
mkdir -p "$PKG/deps"
while IFS= read -r line; do
    dep=${line%% *}
    rel=$(printf '%s' "$line" | sed -n 's/.*path[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$dep" ] && [ -n "$rel" ] || continue
    [ -e "$PKG/deps/$dep" ] && continue
    ( cd "$PKG/deps" && ln -sfn "../$rel" "$dep" )
done < <(sed -n '/^\[dependencies\]/,/^\[/p' "$PKG/nurl.toml" | grep 'path[[:space:]]*=')

# ── build both halves ───────────────────────────────────────────
build_err=$(mktemp)
if ! "$ROOT/unikernel/build_unikernel.sh" "$ROOT/packages/swarm-mcp/src/main.nu" \
        -o "$OUTDIR/swarm_appliance.elf" >"$build_err" 2>&1; then
    # A gate that cannot say WHY a build failed costs a CI round trip
    # per guess — this one cost exactly that.
    say "FAIL: guest image did not build"
    tail -6 "$build_err" | sed 's/^/swarm_gate:   /'
    rm -f "$build_err"
    exit 1
fi

HOSTBIN="$OUTDIR/swarm_gate_host"
if ! ( cd "$PKG" && "$ROOT/nurl.sh" src/main.nu "$HOSTBIN" >"$build_err" 2>&1 ); then
    say "FAIL: host-side swarm-mcp did not build"
    tail -6 "$build_err" | sed 's/^/swarm_gate:   /'
    rm -f "$build_err"
    exit 1
fi
rm -f "$build_err"

# ── the host node: relay + MCP, no worker (the guest is the fleet) ──
node_log=$(mktemp)
guest_log=$(mktemp)
"$HOSTBIN" --token "$TOKEN" --relay --mcp \
    --listen "127.0.0.1:$RELAY_PORT" --mcp-listen "127.0.0.1:$MCP_PORT" \
    > "$node_log" 2>&1 &
node_pid=$!

qemu_pid=""
cleanup() {
    [ -n "$qemu_pid" ] && kill "$qemu_pid" 2>/dev/null
    kill "$node_pid" 2>/dev/null
    sleep 1
    kill -9 "$node_pid" 2>/dev/null   # a wedged node must not wedge the gate
    wait "$node_pid" 2>/dev/null
    rm -f "$node_log" "$guest_log"
}
trap cleanup EXIT

mcp() {  # mcp <json-params>  → tool-call response body (empty on error)
    curl -sk --max-time 15 -X POST "https://127.0.0.1:$MCP_PORT/mcp" \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":$1}" \
        2>/dev/null
}

for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    [ -n "$(mcp '{"name":"swarm_status","arguments":{}}')" ] && break
done
if [ -z "$(mcp '{"name":"swarm_status","arguments":{}}')" ]; then
    say "FAIL: the host node's MCP endpoint never answered"
    head -6 "$node_log" | sed 's/^/swarm_gate:   /'
    exit 1
fi

# ── boot the guest worker; the clock starts HERE (cold start) ───
t0=$(date +%s)
( NURL_APPEND="args=\"--worker --connect 10.0.2.2:$RELAY_PORT --token $TOKEN\"" \
    "$ROOT/unikernel/run_qemu.sh" "$OUTDIR/swarm_appliance.elf" -t 900 -- \
    -netdev user,id=n0 -device virtio-net-device,netdev=n0 \
    > "$guest_log" 2>&1 ) &
qemu_pid=$!

joined=0
for _ in $(seq 1 90); do
    sleep 5
    if mcp '{"name":"swarm_status","arguments":{}}' | grep -q 'workers\\":1'; then
        joined=1; break
    fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then break; fi
done
if [ "$joined" != 1 ]; then
    say "FAIL: the guest worker never appeared in the census"
    tail -8 "$guest_log" | sed 's/^/swarm_gate:   /'
    exit 1
fi
say "guest worker joined the census ($(( $(date +%s) - t0 )) s after launch)"

# ── expr: boot → relay → dispatch → reduce, no wasm in the path ──
expr_out=$(mcp '{"name":"compute_submit","arguments":{"expr":"x*x","lo":0,"hi":1000,"reduce":"sum"}}')
if ! printf '%s' "$expr_out" | grep -q '332833500'; then
    say "FAIL: expr task did not answer 332833500"
    printf 'swarm_gate:   %.200s\n' "$expr_out"
    exit 1
fi
t1=$(date +%s)
say "expr answered 332833500 — cold start to first completed answer: $((t1 - t0)) s (TCG floor)"

# ── wasm: compiled on the host, run IN-PROCESS in the guest ─────
have_zig=0
if [ -n "${NURL_ZIG:-}" ] && [ -x "${NURL_ZIG:-}" ]; then have_zig=1
elif [ -x "${NURL_HOME:-$HOME/.nurl}/zig/zig" ]; then have_zig=1
elif command -v zig >/dev/null 2>&1; then have_zig=1
fi
if [ "$have_zig" != 1 ]; then
    say "SKIP wasm: no zig for wasmbuilder — the expr half gated; install zig (or set NURL_ZIG) to gate the wasm engine too"
    say "verified: census + expr through the guest (wasm SKIPPED, said so above)"
    exit 0
fi

sub=$(mcp '{"name":"compute_submit_kernel","arguments":{"source":"@ kernel i x → i { ^ * x x }","lo":0,"hi":100,"reduce":"sum"}}')
task_id=$(printf '%s' "$sub" | grep -o 'task_id\\":[0-9]*' | head -1 | grep -o '[0-9]*')
if [ -z "$task_id" ]; then
    say "FAIL: compute_submit_kernel returned no task id"
    printf 'swarm_gate:   %.300s\n' "$sub"
    exit 1
fi
if printf '%s' "$sub" | grep -q '328350'; then
    res="$sub"
else
    res=""
    for _ in $(seq 1 120); do
        sleep 10
        res=$(mcp "{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$task_id}}")
        printf '%s' "$res" | grep -q '\\"status\\":\\"done\\"' && break
        printf '%s' "$res" | grep -q '\\"error\\"' && break
        if ! kill -0 "$qemu_pid" 2>/dev/null; then res=""; break; fi
    done
fi
if ! printf '%s' "$res" | grep -q '328350'; then
    say "FAIL: wasm task did not answer 328350 (the guest runs chunks on the in-process pure-NURL nwasm)"
    printf 'swarm_gate:   %.300s\n' "$res"
    tail -8 "$guest_log" | sed 's/^/swarm_gate:   /'
    exit 1
fi
say "wasm answered 328350 — compiled on the host, executed in-process in the guest"
say "verified: census + expr + wasm through the guest, cold-start-to-answer measured"
exit 0
