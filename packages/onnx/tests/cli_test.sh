#!/bin/sh
# ============================================================
#  packages/onnx — CLI smoke test
#
#  The 0.5.0 tensor bridge changed RTensor's shape and the CLI's one use of
#  the old fields (rows/cols) went unnoticed for months: the .nu tests cover
#  rt_run directly, so the package "passed" while its entry point did not
#  compile. This builds src/main.nu and runs the whole thing — parse, upload,
#  execute, download, compare — against the checked-in onnxruntime reference.
#
#  Run from the package dir:  ./tests/cli_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t onnxcli.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/2] build the CLI"
if ! $NURL src/main.nu "$WORK/onnx" >/dev/null 2>"$WORK/build.err"; then
    echo "  build FAILED"; cat "$WORK/build.err"; exit 1
fi

echo "[2/2] run tiny.onnx end to end against the onnxruntime reference"
OUT=$("$WORK/onnx" tests/data/tiny.onnx tests/data/tiny.in.f32 tests/data/tiny.out.f32 2>&1)
printf '%s\n' "$OUT" | grep -q "MATCH" \
    && echo "  PASS the CLI parses, runs and matches the reference" \
    || { echo "  FAIL"; printf '%s\n' "$OUT"; exit 1; }
