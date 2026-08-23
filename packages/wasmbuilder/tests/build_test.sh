#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/build_test.sh — wasmbuilder end-to-end test.
#
#  1. builds the wasmbuilder CLI with the toolchain
#  2. compiles a corpus of repo examples to wasm32-wasi
#  3. runs each next to its native build and diffs the output
#     (skipped per-module if no wasm runtime is available)
#  4. runs the IR-rewriter unit test (string constants survive)
#  5. runs the library-API test (wb_build_source)
#
#  Run from the package dir:  ./tests/build_test.sh
#  Env:
#    NURL          build driver (default: ../../nurl.sh, else nurl on PATH)
#    WASM_RUNTIME  wasm runner (default: wasmtime on PATH, else skip runs)
# ============================================================
set -u
cd "$(dirname "$0")/.."
PKG_DIR="$PWD"
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then
    NURL="$REPO_ROOT/nurl.sh"
    export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}"
    # Pin wasmbuilder's nurlc to the same freshly-built compiler that
    # builds the native twins — otherwise it resolves the installed
    # $NURL_HOME/bin/nurlc, and a corpus entry exercising new codegen
    # (e.g. the i64 enum-payload slots) would diff against stale output.
    if [ -x "$REPO_ROOT/build/nurlc" ]; then export NURLC="${NURLC:-$REPO_ROOT/build/nurlc}"; fi
else NURL="nurl"; fi

RUNTIME="${WASM_RUNTIME:-}"
if [ -z "$RUNTIME" ] && command -v wasmtime >/dev/null 2>&1; then RUNTIME="wasmtime"; fi

WORK="$(mktemp -d -t wasmbuilder-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

echo "[1/4] build wasmbuilder"
if ! $NURL src/main.nu "$WORK/wasmbuilder" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build wasmbuilder:"; tail -5 "$WORK/build.err"; exit 1
fi

echo "[2/4] corpus: native vs wasm output"
# Deterministic, dependency-free examples. (uuidgen etc. are random by
# design and can't be diffed.) chaotic-showcase and the
# enum_payload_64bit_slots compiler test guard the i64 enum-payload
# slots: both carry f64 / >2^32 payloads that a pre-fix nurlc truncated
# on wasm32 (they need a toolchain with the i64-slot enum layout).
# find_clone is here for its import graph, not its no-args usage run: it
# pulls std/path.nu (realpath) and std/process.nu (fork/waitpid/mmap), the
# POSIX-stub surface of wasi_ir.nu. Its wasm build broke silently when
# path_canonical entered the stdlib import graph — realpath's prelude
# declare is column-padded ("i8*  @realpath") and the stub stripper
# rebuilt the line with single spacing, so nothing in this corpus caught it.
CORPUS="fizzbuzz collatz math_basic json_basic showcase serde_demo msgpack_demo dict_coder enigma rule30 slice_test test_05_closures_and_capture test_06_torture_chamber chaotic-showcase find_clone tests:enum_payload_64bit_slots"
for name in $CORPUS; do
    case "$name" in
        tests:*) src="$REPO_ROOT/compiler/tests/${name#tests:}.nu" ;;
        *)       src="$REPO_ROOT/examples/$name.nu" ;;
    esac
    [ -f "$src" ] || { echo "  SKIP $name (example missing)"; continue; }
    if ! $NURL "$src" "$WORK/$name.native" >/dev/null 2>&1; then
        echo "  SKIP $name (native build failed)"; continue
    fi
    if ! "$WORK/wasmbuilder" --quiet "$src" -o "$WORK/$name.wasm" 2>"$WORK/$name.err"; then
        echo "  FAIL $name (wasm build): $(tail -1 "$WORK/$name.err")"; FAIL=$((FAIL+1)); continue
    fi
    if [ -z "$RUNTIME" ]; then
        echo "  PASS $name (built; no wasm runtime to run it)"; PASS=$((PASS+1)); continue
    fi
    (cd "$WORK" && "./$name.native" > "$name.n.out" 2>&1); nrc=$?
    (cd "$WORK" && timeout 120 "$RUNTIME" "$name.wasm" > "$name.w.out" 2>&1); wrc=$?
    if [ "$nrc" = "$wrc" ] && cmp -s "$WORK/$name.n.out" "$WORK/$name.w.out"; then
        echo "  PASS $name (rc=$nrc, output identical)"; PASS=$((PASS+1))
    else
        echo "  FAIL $name (native rc=$nrc, wasm rc=$wrc)"; FAIL=$((FAIL+1))
    fi
done

echo "[3/4] IR rewriter (wb_prepare_ir_for_wasi)"
if $NURL tests/ir_test.nu "$WORK/ir_test" >/dev/null 2>"$WORK/ir.err" && "$WORK/ir_test"; then
    PASS=$((PASS+1))
else
    echo "  FAIL ir_test"; tail -3 "$WORK/ir.err" 2>/dev/null; FAIL=$((FAIL+1))
fi

echo "[4/4] library API (wb_build_source)"
if $NURL tests/lib_test.nu "$WORK/lib_test" >/dev/null 2>"$WORK/lib.err" && "$WORK/lib_test"; then
    PASS=$((PASS+1))
else
    echo "  FAIL lib_test"; tail -3 "$WORK/lib.err" 2>/dev/null; FAIL=$((FAIL+1))
fi

echo "== wasmbuilder tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
