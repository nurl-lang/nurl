#!/bin/sh
# ============================================================
#  packages/lingbot-map — test suite
#
#  Each module is checked against the reference PyTorch implementation
#  it was ported from. The oracle scripts under tests/ re-run the exact
#  upstream code paths, so a mismatch means the port is wrong, not that
#  the reference moved.
#
#  Tolerance, not byte equality: torch's vectorised libm (SLEEF) and
#  glibc's differ by an ULP on transcendentals — `tan` here — and that
#  ULP then propagates through the intrinsics into every unprojected
#  point. 1e-12 relative is four orders tighter than anything that could
#  hide a real porting error (a swapped index, a transposed matrix, a
#  scalar-first quaternion) while ignoring the last bit.
#
#  Needs a python with torch — set PYTORCH_PY, or the repo's
#  .venv-oracle is used when present.
#
#  Run from the package dir:  ./tests/lingbot_map_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

if [ -n "${PYTORCH_PY:-}" ]; then :;
elif [ -x "$REPO_ROOT/.venv-oracle/bin/python" ]; then PYTORCH_PY="$REPO_ROOT/.venv-oracle/bin/python";
else PYTORCH_PY=""; fi

WORK="$(mktemp -d -t lingbotmap.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP $1"; SKIP=$((SKIP+1)); }

# compare two "<label> <v0> <v1> …" files numerically
cmp_rows() {
    "$PYTORCH_PY" - "$1" "$2" "$3" <<'PY'
import sys
ref, got, tol = open(sys.argv[1]).read().split("\n"), open(sys.argv[2]).read().split("\n"), float(sys.argv[3])
if len(ref) != len(got):
    print("line count differs: %d vs %d" % (len(ref), len(got))); sys.exit(1)
worst, where = 0.0, ""
for n, (a, b) in enumerate(zip(ref, got), 1):
    ta, tb = a.split(), b.split()
    if len(ta) != len(tb) or (ta and tb and ta[0] != tb[0]):
        print("line %d shape/label differs:\n  %s\n  %s" % (n, a, b)); sys.exit(1)
    for x, y in zip(ta[1:], tb[1:]):
        fx, fy = float(x), float(y)
        d = abs(fx - fy) / max(1.0, abs(fx))
        if d > worst:
            worst, where = d, "line %d: %r vs %r" % (n, fx, fy)
if worst > tol:
    print("worst relative error %.3e > %.0e  (%s)" % (worst, tol, where)); sys.exit(1)
print("worst relative error %.3e" % worst)
PY
}

echo "[1/3] camera geometry vs the reference torch code"
if ! $NURL tests/geomcheck.nu "$WORK/geomcheck" >/dev/null 2>"$WORK/build.err"; then
    bad "geomcheck build"; cat "$WORK/build.err"
elif [ -z "$PYTORCH_PY" ] || ! "$PYTORCH_PY" -c "import torch" 2>/dev/null; then
    "$WORK/geomcheck" >/dev/null 2>&1 && ok "geomcheck runs (oracle skipped: no torch)" \
        || bad "geomcheck crashed"
    skip "oracle comparison — set PYTORCH_PY"
else
    "$WORK/geomcheck" > "$WORK/nurl.txt" 2>&1
    "$PYTORCH_PY" tests/geom_oracle.py > "$WORK/ref.txt" 2>&1
    if out="$(cmp_rows "$WORK/ref.txt" "$WORK/nurl.txt" 1e-12)"; then
        ok "quat/extri/intri/c2w/unproject match torch — $out"
    else
        bad "geometry differs from torch"; echo "$out"
    fi
fi

echo "[2/3] frame preprocessing vs the reference load_fn pipeline"
# Real frames, not synthetic ones: the resize ratio, the patch-multiple
# rounding and the centre crop only interact on an actual aspect ratio.
FRAMES=""
for d in courthouse loop university; do
    for n in 000000 000001; do
        p="$HOME/dev/lingbot-map/example/$d/$n.png"
        [ -f "$p" ] && FRAMES="$FRAMES $p"
    done
done
if ! $NURL tests/preproccheck.nu "$WORK/ppc" >/dev/null 2>"$WORK/pp_build.err"; then
    bad "preproccheck build"; tail -6 "$WORK/pp_build.err"
elif [ -z "$FRAMES" ]; then
    skip "no example frames (expected under ~/dev/lingbot-map/example/)"
elif [ -z "$PYTORCH_PY" ] || ! "$PYTORCH_PY" -c "import PIL" 2>/dev/null; then
    skip "preprocessing oracle — needs python + Pillow"
else
    # shellcheck disable=SC2086
    "$WORK/ppc" $FRAMES > "$WORK/pp_nurl.txt" 2>&1
    # shellcheck disable=SC2086
    "$PYTORCH_PY" tests/preproc_oracle.py $FRAMES > "$WORK/pp_ref.txt" 2>&1
    if cmp -s "$WORK/pp_ref.txt" "$WORK/pp_nurl.txt"; then
        ok "$(wc -l < "$WORK/pp_ref.txt" | tr -d ' ') frames identical to the reference pipeline"
    else
        bad "preprocessing differs from the reference"
        diff "$WORK/pp_ref.txt" "$WORK/pp_nurl.txt" | head -4 | cut -c1-200
    fi
fi

echo "[3/3] position-grid resample vs torch bicubic+antialias"
if ! $NURL tests/interpcheck.nu "$WORK/ic" >/dev/null 2>"$WORK/ic_build.err"; then
    bad "interpcheck build"; tail -6 "$WORK/ic_build.err"
elif [ -z "$PYTORCH_PY" ] || ! "$PYTORCH_PY" -c "import torch" 2>/dev/null; then
    skip "resample oracle — needs python + torch"
else
    "$WORK/ic" > "$WORK/ic_nurl.txt" 2>&1
    "$PYTORCH_PY" tests/interp_oracle.py > "$WORK/ic_ref.txt" 2>&1
    if out="$(cmp_rows "$WORK/ic_ref.txt" "$WORK/ic_nurl.txt" 1e-12)"; then
        ok "bicubic+antialias matches torch — $out"
    else
        bad "resample differs from torch"; echo "$out"
    fi
fi

echo
echo "lingbot-map: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
