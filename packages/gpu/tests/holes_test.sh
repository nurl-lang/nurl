#!/usr/bin/env bash
# ============================================================
#  tests/holes_test.sh — the gpu package's soundness probes. Each
#  tests/holes/*.nu is SAFE code reaching for memory it does not own
#  through the package: every one must be refused by the compiler, except
#  the ones marked `// RUNS:`, which must build and stop with a panic
#  instead of reading or writing past a buffer.
#
#  Run from the package dir:  ./tests/holes_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
WORK="$(mktemp -d -t gpu-holes.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
for f in tests/holes/*.nu; do
    b="$WORK/$(basename "$f" .nu)"
    if grep -q '^// RUNS:' "$f"; then
        if ! $NURL "$f" "$b" >/dev/null 2>"$b.err"; then echo "  FAIL $f: did not build"; FAIL=$((FAIL+1)); continue; fi
        out=$(NURL_GPU=cpu "$b" 2>&1); rc=$?
        if [ $rc -ne 0 ] && grep -q 'index out of bounds' <<<"$out"; then echo "  PASS $f (panics)"; PASS=$((PASS+1));
        else echo "  FAIL $f: rc=$rc, no bounds panic"; FAIL=$((FAIL+1)); fi
    else
        if $NURL "$f" "$b" >/dev/null 2>"$b.err"; then echo "  FAIL $f: compiled"; FAIL=$((FAIL+1));
        else echo "  PASS $f: $(grep -m1 -oE 'error: .{0,70}' "$b.err")"; PASS=$((PASS+1)); fi
    fi
done
echo "holes: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
