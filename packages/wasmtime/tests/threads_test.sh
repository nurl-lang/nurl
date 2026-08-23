#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/threads_test.sh — wasi-threads end to end.
#
#  The same NURL program is built native and as a wasm32-wasi module
#  with --threads, and both runs must print the same thing. On the wasm
#  side that means: a shared memory, `wasi.thread-spawn`, one instance
#  per thread over one linear memory, the 0xfe atomics behind the
#  guest's mutex, and a heap that survives four threads growing it.
#
#  Run from the package dir:  ./tests/threads_test.sh
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

WORK="$(mktemp -d -t wt-threads-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

echo "[1/3] build wt + the probe (native)"
$NURL src/main.nu "$WORK/wt" >/dev/null 2>"$WORK/wt.err" || { echo "FAIL: could not build wt:"; tail -5 "$WORK/wt.err"; exit 1; }
$NURL tests/progs/threadprobe.nu "$WORK/probe.native" >/dev/null 2>"$WORK/n.err" || { echo "FAIL: native probe:"; tail -5 "$WORK/n.err"; exit 1; }

echo "[2/3] build the probe for wasi-threads"
WB="${WASMBUILDER:-}"
if [ -z "$WB" ] && [ -d "$REPO_ROOT/packages/wasmbuilder" ]; then
    $NURL "$REPO_ROOT/packages/wasmbuilder/src/main.nu" "$WORK/wasmbuilder" >/dev/null 2>"$WORK/wb.err" && WB="$WORK/wasmbuilder"
fi
[ -n "$WB" ] || { echo "  SKIP (no wasmbuilder available)"; exit 0; }
if ! "$WB" --quiet --threads tests/progs/threadprobe.nu -o "$WORK/probe.wasm" 2>"$WORK/w.err"; then
    echo "FAIL: wasm build:"; tail -5 "$WORK/w.err"; exit 1
fi

echo "[3/3] native vs wasm output"
"$WORK/probe.native" > "$WORK/n.out" 2>&1; nrc=$?
timeout 600 "$WORK/wt" run "$WORK/probe.wasm" > "$WORK/w.out" 2>&1; wrc=$?
# Both must actually have run four threads — two identical failures would
# otherwise "match" and pass a runtime that spawns nothing at all.
if ! grep -q "^threads: 4$" "$WORK/n.out" || ! grep -q "^total: 640000$" "$WORK/n.out"; then
    echo "  FAIL native probe did not run:"; cat "$WORK/n.out"; FAIL=$((FAIL+1))
elif [ "$nrc" = "$wrc" ] && cmp -s "$WORK/n.out" "$WORK/w.out"; then
    echo "  PASS 4 threads, shared heap (rc=$nrc, output identical)"; PASS=$((PASS+1))
else
    echo "  FAIL (native rc=$nrc, wasm rc=$wrc)"; diff "$WORK/n.out" "$WORK/w.out" | head -10; FAIL=$((FAIL+1))
fi

echo "== wasmtime threads tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
