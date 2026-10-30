#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  nurlapi/e2e_local.sh — the playground server built from THIS checkout
#  and driven end to end, without Docker: compile nurlapi/main.nu, run
#  it against the repo's own compiler, stdlib, docs, formal/, examples
#  and tests, and run e2e_test.py at it.
#
#  Usage (repo root, after ./build.sh):
#      ./nurlapi/e2e_local.sh                 # native build + MCP surface
#      ./nurlapi/e2e_local.sh --quick         # MCP surface only
#      ./nurlapi/e2e_local.sh --full          # + wasm and unikernel builds
#                                             #   (needs WASI_CLANG, the
#                                             #   wasm runtime objects, qemu)
#  Env: E2E_PORT (default 18000).
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODE="--native-only"
case "${1:-}" in
    --quick) MODE="--quick" ;;
    --full) MODE="" ;;
esac
PORT="${E2E_PORT:-18000}"
WORK="$(mktemp -d)"
mkdir -p "$WORK/out"
./nurl.sh nurlapi/main.nu "$WORK/nurlapi" >/dev/null
# The build sandbox (Agora #207): the wrapper and what it confines, then
# every build below runs under it — required wherever the kernel has
# Landlock, so a tool the policy breaks fails this run.
cc -O2 -Wall -Wextra -Werror -std=c11 -o "$WORK/nurl-sandbox" nurlapi/sandbox/nurl_sandbox.c
bash nurlapi/sandbox/sandbox_test.sh "$WORK/nurl-sandbox"
SANDBOX_MODE=auto
case "$("$WORK/nurl-sandbox" --probe)" in landlock*) SANDBOX_MODE=required ;; esac
export NURL_SANDBOX_BIN="$WORK/nurl-sandbox" NURL_SANDBOX="$SANDBOX_MODE"
[ "$SANDBOX_MODE" = required ] && export E2E_EXPECT_SANDBOX=1
export NURLC_PATH="$ROOT/build/nurlc" NURL_STDLIB_DIR="$ROOT/stdlib" NURL_OUTPUT_DIR="$WORK/out" \
    NURL_EXAMPLES_DIR="$ROOT/examples" NURL_WORK_ROOT="$ROOT" NURL_STATIC_DIR="$ROOT/nurlapi/static" \
    NURL_README_PATH="$ROOT/README.md" NURL_GRAMMAR_PATH="$ROOT/spec/grammar.ebnf" \
    NURL_TESTS_DIR="$ROOT/compiler/tests" NURL_ROADMAP_PATH="$ROOT/ROADMAP.md" NURL_DOCS_DIR="$ROOT/docs" \
    NURL_CHANGELOG_PATH="$ROOT/CHANGELOG.md" NURL_PORT="$PORT" \
    NURL_BUILDS_PER_MIN=10000 NURL_MCP_PER_MIN=10000 \
    NURL_UNIKERNEL_BUILD="$ROOT/unikernel/build_unikernel.sh" \
    NURL_UNIKERNEL_BUILD_ARM64="$ROOT/unikernel/build_unikernel_arm64.sh"
"$WORK/nurlapi" > "$WORK/server.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -rf "$WORK"' EXIT
rc=0
python3 nurlapi/e2e_test.py --base "http://127.0.0.1:$PORT" $MODE || rc=$?
if [ $rc -ne 0 ]; then echo "--- server log (tail) ---"; tail -40 "$WORK/server.log"; ls -la "$WORK/out" | head; fi
exit $rc
