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

echo "[1/9] camera geometry vs the reference torch code"
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

echo "[2/9] frame preprocessing vs the reference load_fn pipeline"
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

echo "[3/9] position-grid resample vs torch bicubic+antialias"
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

echo "[4/9] 2-D rotary position embedding vs the reference"
if ! $NURL tests/ropecheck.nu "$WORK/rc" >/dev/null 2>"$WORK/rc_build.err"; then
    bad "ropecheck build"; tail -6 "$WORK/rc_build.err"
elif [ -z "$PYTORCH_PY" ] || ! "$PYTORCH_PY" -c "import torch" 2>/dev/null; then
    skip "rope oracle — needs python + torch"
else
    "$WORK/rc" > "$WORK/rc_nurl.txt" 2>&1
    "$PYTORCH_PY" tests/rope_oracle.py > "$WORK/rc_ref.txt" 2>&1
    if out="$(cmp_rows "$WORK/rc_ref.txt" "$WORK/rc_nurl.txt" 1e-14)"; then
        ok "rope2d matches RotaryPositionEmbedding2D — $out"
    else
        bad "rope2d differs from the reference"; echo "$out"
    fi
fi

echo "[5/9] patch embedding vs torch Conv2d"
if ! $NURL tests/pecheck.nu "$WORK/pe" >/dev/null 2>"$WORK/pe_build.err"; then
    bad "pecheck build"; tail -6 "$WORK/pe_build.err"
elif [ -z "$PYTORCH_PY" ] || ! "$PYTORCH_PY" -c "import torch" 2>/dev/null; then
    skip "patch-embed oracle — needs python + torch"
else
    "$WORK/pe" > "$WORK/pe_nurl.txt" 2>&1
    "$PYTORCH_PY" tests/pe_oracle.py > "$WORK/pe_ref.txt" 2>&1
    if out="$(cmp_rows "$WORK/pe_ref.txt" "$WORK/pe_nurl.txt" 1e-12)"; then
        ok "im2col + project matches Conv2d — $out"
    else
        bad "patch embedding differs from torch"; echo "$out"
    fi
fi

echo "[6/9] full transformer block vs the reference Block"
if ! $NURL tests/blockcheck.nu "$WORK/bc" >/dev/null 2>"$WORK/bc_build.err"; then
    bad "blockcheck build"; tail -6 "$WORK/bc_build.err"
elif [ -z "$PYTORCH_PY" ] || ! "$PYTORCH_PY" -c "import torch" 2>/dev/null; then
    skip "block oracle — needs python + torch"
else
    "$WORK/bc" > "$WORK/bc_nurl.txt" 2>&1
    "$PYTORCH_PY" tests/block_oracle.py > "$WORK/bc_ref.txt" 2>&1
    if out="$(cmp_rows "$WORK/bc_ref.txt" "$WORK/bc_nurl.txt" 1e-12)"; then
        ok "layernorm + qk-norm attention + rope + gelu MLP + layerscale — $out"
    else
        bad "block differs from the reference"; echo "$out"
    fi
fi

echo "[7/9] the real 4.6 GB checkpoint (skipped when absent)"
CKPT="${LINGBOT_CKPT:-$HOME/.nurl/models/lingbot-map/lingbot-map.pt}"
if [ ! -f "$CKPT" ]; then
    skip "no checkpoint at $CKPT — set LINGBOT_CKPT"
elif ! $NURL tests/wcheck.nu "$WORK/wc" >/dev/null 2>"$WORK/wc_build.err"; then
    bad "wcheck build"; tail -6 "$WORK/wc_build.err"
else
    "$WORK/wc" "$CKPT" > "$WORK/wc.txt" 2>&1
    # The architecture the file actually describes — a zip64 archive past
    # 4 GiB, read through mmap without loading it.
    if grep -q "^tensors 1342$" "$WORK/wc.txt" &&
       grep -q "^dino_blocks 24$" "$WORK/wc.txt" &&
       grep -q "^frame_blocks 24$" "$WORK/wc.txt" &&
       grep -q "^global_blocks 24$" "$WORK/wc.txt" &&
       grep -q "^shape_contract OK$" "$WORK/wc.txt" &&
       grep -q "^point_head_present F$" "$WORK/wc.txt" &&
       grep -q "^read_ls1 OK n=1024 v0=0.0011749680852517486 v1023=0.000993272173218429$" "$WORK/wc.txt"; then
        ok "1342 tensors, 24/24/24 blocks, values identical to torch.load"
    else
        bad "real checkpoint reads wrong"; cat "$WORK/wc.txt"
    fi
fi

echo "[8/9] the block on the DEVICE (f32) vs the host reference"
# Tolerance is float32's, not float64's: the device path computes in f32
# on purpose. 1e-4 is two orders above what is observed (~3e-6) and two
# orders below what any real stride bug produces (a wrong head stride
# measured ~9e-2 while this was being written).
if ! $NURL tests/devblockcheck.nu "$WORK/dbc" >/dev/null 2>"$WORK/dbc_build.err"; then
    bad "devblockcheck build"; tail -6 "$WORK/dbc_build.err"
else
    "$WORK/dbc" > "$WORK/dbc.txt" 2>&1
    if grep -q "no gpukit backend" "$WORK/dbc.txt"; then
        skip "no gpukit backend available"
    elif grep -q "FAILED" "$WORK/dbc.txt"; then
        bad "device block failed to run"; cat "$WORK/dbc.txt"
    else
        WORST=$(sed -n 's/.*worst=//p' "$WORK/dbc.txt" | sort -g | tail -1)
        NCASE=$(grep -c "worst=" "$WORK/dbc.txt")
        if [ "$NCASE" -ge 4 ] && awk "BEGIN{exit !($WORST < 1e-4)}"; then
            ok "$NCASE cases on $(sed -n 's/^backend //p' "$WORK/dbc.txt"), worst $WORST vs the f64 reference"
        else
            bad "device block differs: worst=$WORST over $NCASE cases"; cat "$WORK/dbc.txt"
        fi
    fi
fi

echo "[9/9] 3-D rope vs the real WanRotaryPosEmbed"
# This one imports the upstream package rather than re-implementing it:
# the 3-D rope is fiddly enough (three axes, interleaved pairs, a 20/22/22
# head split) that a hand-written oracle would just be a second chance to
# make the same mistake.
if ! $NURL tests/rope3check.nu "$WORK/r3" >/dev/null 2>"$WORK/r3_build.err"; then
    bad "rope3check build"; tail -6 "$WORK/r3_build.err"
elif [ -z "$PYTORCH_PY" ] ||
     ! "$PYTORCH_PY" -c "import sys,os;sys.path.insert(0,os.path.expanduser('~/dev/lingbot-map'));import lingbot_map.layers.rope" 2>/dev/null; then
    skip "needs the upstream lingbot_map package importable (~/dev/lingbot-map)"
else
    "$WORK/r3" > "$WORK/r3_nurl.txt" 2>&1
    "$PYTORCH_PY" tests/rope3_oracle.py 2>/dev/null | grep -E "^w[0-9]" > "$WORK/r3_ref.txt"
    if out="$(cmp_rows "$WORK/r3_ref.txt" "$WORK/r3_nurl.txt" 1e-14)"; then
        ok "rope3d matches WanRotaryPosEmbed + apply_rotary_emb — $out"
    else
        bad "rope3d differs from the reference"; echo "$out"
    fi
fi

echo
echo "lingbot-map: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
