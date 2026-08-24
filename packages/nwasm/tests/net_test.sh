#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/net_test.sh — the `nurl_net` host-import bridge, end to end.
#
#  A NURL program that opens sockets is built twice — native and
#  wasm32-wasi — and both runs must print the same thing. The wasm one
#  reaches the network only through this runtime's import bridge, so the
#  comparison is the whole point: same stdlib, same TLS-capable socket
#  API, one of them going through wasm imports.
#
#  Also asserts the capability gate: without --allow-net the module
#  traps instead of quietly opening a socket.
#
#  Run from the package dir:  ./tests/net_test.sh
#  Env:
#    NURL          build driver (default: ../../nurl.sh, else nurl)
#    WASMBUILDER   wasm builder (default: build ../wasmbuilder)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then
    NURL="$REPO_ROOT/nurl.sh"
    export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}"
    if [ -x "$REPO_ROOT/build/nurlc" ]; then export NURLC="${NURLC:-$REPO_ROOT/build/nurlc}"; fi
else NURL="nurl"; fi

WORK="$(mktemp -d -t nwasm-net-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

echo "[1/4] build nwasm + the probe (native)"
if ! $NURL src/main.nu "$WORK/nwasm" >/dev/null 2>"$WORK/nwasm.err"; then
    echo "FAIL: could not build nwasm:"; tail -5 "$WORK/nwasm.err"; exit 1
fi
if ! $NURL tests/progs/netprobe.nu "$WORK/netprobe.native" >/dev/null 2>"$WORK/n.err"; then
    echo "FAIL: could not build the native probe:"; tail -5 "$WORK/n.err"; exit 1
fi

echo "[2/4] build the probe for wasm32-wasi"
WB="${WASMBUILDER:-}"
if [ -z "$WB" ]; then
    if [ -d "$REPO_ROOT/packages/wasmbuilder" ]; then
        if $NURL "$REPO_ROOT/packages/wasmbuilder/src/main.nu" "$WORK/wasmbuilder" >/dev/null 2>"$WORK/wb.err"; then
            WB="$WORK/wasmbuilder"
        fi
    fi
fi
if [ -z "$WB" ]; then
    echo "  SKIP (no wasmbuilder available to produce the wasm side)"
    exit 0
fi
if ! "$WB" --quiet tests/progs/netprobe.nu -o "$WORK/netprobe.wasm" 2>"$WORK/w.err"; then
    echo "FAIL: wasm build:"; tail -5 "$WORK/w.err"; FAIL=$((FAIL+1))
fi

echo "[3/4] capability gate: no --allow-net must trap"
if [ -f "$WORK/netprobe.wasm" ]; then
    gate="$("$WORK/nwasm" run "$WORK/netprobe.wasm" 2>&1)"
    case "$gate" in
        *"--allow-net"*) echo "  PASS gate (trapped: sockets are opt-in)"; PASS=$((PASS+1)) ;;
        *) echo "  FAIL gate — expected a trap naming --allow-net, got:"; echo "$gate" | head -3; FAIL=$((FAIL+1)) ;;
    esac
fi

echo "[4/4] native vs wasm output"
if [ -f "$WORK/netprobe.wasm" ]; then
    "$WORK/netprobe.native" > "$WORK/n.out" 2>&1; nrc=$?
    timeout 600 "$WORK/nwasm" run --allow-net "$WORK/netprobe.wasm" > "$WORK/w.out" 2>&1; wrc=$?
    # The probe must actually have done the round trip — a pair of empty
    # outputs would otherwise "match" and pass a broken bridge.
    if ! grep -q "server read: ping over wasm" "$WORK/n.out"; then
        echo "  FAIL native probe did not complete:"; cat "$WORK/n.out"; FAIL=$((FAIL+1))
    elif [ "$nrc" = "$wrc" ] && cmp -s "$WORK/n.out" "$WORK/w.out"; then
        echo "  PASS round trip (rc=$nrc, output identical)"; PASS=$((PASS+1))
    else
        echo "  FAIL (native rc=$nrc, wasm rc=$wrc)"; diff "$WORK/n.out" "$WORK/w.out" | head -10; FAIL=$((FAIL+1))
    fi
fi

echo "== nwasm net tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
