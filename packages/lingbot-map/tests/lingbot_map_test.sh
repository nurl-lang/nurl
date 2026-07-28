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

# kv_oracle.py is plain python — no torch, no checkpoint — so it runs
# even where the model cannot.
if [ -n "${PY:-}" ]; then :;
elif command -v python3 >/dev/null 2>&1; then PY="python3";
else PY="$PYTORCH_PY"; fi

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

echo "[1/22] camera geometry vs the reference torch code"
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

echo "[2/22] frame preprocessing vs the reference load_fn pipeline"
# Real frames, not synthetic ones: the resize ratio, the patch-multiple
# rounding and the centre crop only interact on an actual aspect ratio.
FRAMES=""
for d in courthouse loop university; do
    for n in 000000 000001; do
        p="$HOME/dev/lingbot-map/example/$d/$n.png"
        [ -f "$p" ] && FRAMES="$FRAMES $p"
    done
done
# A PORTRAIT frame too: the crop path where the resized height overshoots
# and is centre-cropped back had never met one until a phone video did.
if [ -n "$FRAMES" ] && [ -n "${PYTORCH_PY:-}" ] && \
   "$PYTORCH_PY" -c "import PIL" 2>/dev/null; then
    WORK="$WORK" "$PYTORCH_PY" -c "
import os
from PIL import Image
src = os.path.expanduser('~/dev/lingbot-map/example/courthouse/000000.png')
Image.open(src).transpose(Image.ROTATE_90).save(os.environ['WORK'] + '/portrait.png')
" 2>/dev/null && FRAMES="$FRAMES $WORK/portrait.png"
fi
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

echo "[3/22] position-grid resample vs torch bicubic+antialias"
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

echo "[4/22] 2-D rotary position embedding vs the reference"
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

echo "[5/22] patch embedding vs torch Conv2d"
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

echo "[6/22] full transformer block vs the reference Block"
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

CKPT="${LINGBOT_CKPT:-$HOME/.nurl/models/lingbot-map/lingbot-map.pt}"
echo "[7/22] the real 4.6 GB checkpoint (skipped when absent)"
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

echo "[8/22] the block on the DEVICE (f32) vs the host reference"
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

echo "[9/22] 3-D rope vs the real WanRotaryPosEmbed"
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

echo "[10/22] the DINOv2 trunk on a real frame vs the real model"
# 24 blocks and 300M real weights against tests/agg_ref_courthouse0.txt,
# which tests/agg_oracle.py produced by running the actual model. Takes
# ~35 s and ~2.5 GB. Tolerance is float32's.
FRAME0="$HOME/dev/lingbot-map/example/courthouse/000000.png"
if [ ! -f "$CKPT" ]; then
    skip "no checkpoint — set LINGBOT_CKPT"
elif [ ! -f "$FRAME0" ]; then
    skip "no example frame at $FRAME0"
elif [ -z "$PYTORCH_PY" ]; then
    skip "needs python to compare the dumps"
elif ! $NURL tests/dinocheck.nu "$WORK/dc" >/dev/null 2>"$WORK/dc_build.err"; then
    bad "dinocheck build"; tail -6 "$WORK/dc_build.err"
else
    if "$WORK/dc" "$CKPT" "$FRAME0" > "$WORK/dino.txt" 2>"$WORK/dino.err"; then
        if out="$("$PYTORCH_PY" tests/cmp_dump.py tests/agg_ref_courthouse0.txt "$WORK/dino.txt" 1e-4)"; then
            ok "dino_patchtokens — $out"
        else
            bad "DINOv2 trunk differs from the real model"; echo "$out"
        fi
    else
        bad "dinocheck failed to run"; tail -4 "$WORK/dino.err"
    fi
fi

echo "[11/22] the WHOLE aggregator on a real frame vs the real model"
# 72 blocks and 909M real weights: DINOv2 trunk, then 24 frame/global
# pairs with 2-D and 3-D rope and the six special tokens. ~105 s, 7.3 GB.
if [ ! -f "$CKPT" ]; then
    skip "no checkpoint — set LINGBOT_CKPT"
elif [ ! -f "$FRAME0" ]; then
    skip "no example frame at $FRAME0"
elif [ -z "$PYTORCH_PY" ]; then
    skip "needs python to compare the dumps"
elif ! $NURL tests/aggcheck.nu "$WORK/ac" >/dev/null 2>"$WORK/ac_build.err"; then
    bad "aggcheck build"; tail -6 "$WORK/ac_build.err"
else
    if "$WORK/ac" "$CKPT" "$FRAME0" > "$WORK/agg.txt" 2>"$WORK/agg.err"; then
        if grep -q "nan=0" "$WORK/agg.txt"; then
            grep agg_out "$WORK/agg.txt" > "$WORK/agg_out.txt"
            if out="$("$PYTORCH_PY" tests/cmp_dump.py tests/agg_ref_courthouse0.txt \
                      "$WORK/agg_out.txt" 1e-5)"; then
                ok "four tapped layers — $out"
            else
                bad "aggregator differs from the real model"; echo "$out"
            fi
        else
            bad "aggregator produced NaN"; grep tokens "$WORK/agg.txt"
        fi
    else
        bad "aggcheck failed to run"; tail -4 "$WORK/agg.err"
    fi
fi

echo "[12/22] two frames STREAMED through the KV cache"
# The cache is the whole point of the model: frame 2's global blocks
# attend over frame 1's keys as well as their own. ~200 s.
FRAME1="$HOME/dev/lingbot-map/example/courthouse/000001.png"
if [ ! -f "$CKPT" ] || [ ! -f "$FRAME0" ] || [ ! -f "$FRAME1" ]; then
    skip "needs the checkpoint and two example frames"
elif [ -z "$PYTORCH_PY" ]; then
    skip "needs python for the reference and the comparison"
elif ! $NURL tests/streamcheck.nu "$WORK/sc" >/dev/null 2>"$WORK/sc_build.err"; then
    bad "streamcheck build"; tail -6 "$WORK/sc_build.err"
else
    LINGBOT_STREAM=1 "$PYTORCH_PY" tests/agg_oracle.py "$CKPT" "$FRAME0" "$FRAME1" \
        2>/dev/null | grep stream > "$WORK/stream_ref.txt"
    if "$WORK/sc" "$CKPT" "$FRAME0" "$FRAME1" > "$WORK/stream.txt" 2>"$WORK/stream.err"; then
        if out="$("$PYTORCH_PY" tests/cmp_dump.py "$WORK/stream_ref.txt" "$WORK/stream.txt" 1e-5)"; then
            ok "streaming with the KV cache — $out"
        else
            bad "streaming differs from the real model"; echo "$out"
        fi
    else
        bad "streamcheck failed to run"; tail -4 "$WORK/stream.err"
    fi
fi

echo "[13/22] a camera POSE, end to end, vs the real model"
# preprocess -> DINOv2 -> aggregator -> camera head -> 9-vector, then
# decoded to extrinsics and intrinsics. ~106 s.
if [ ! -f "$CKPT" ] || [ ! -f "$FRAME0" ]; then
    skip "needs the checkpoint and an example frame"
elif [ -z "$PYTORCH_PY" ]; then
    skip "needs python to compare the dumps"
elif ! $NURL tests/posecheck.nu "$WORK/pc" >/dev/null 2>"$WORK/pc_build.err"; then
    bad "posecheck build"; tail -6 "$WORK/pc_build.err"
else
    if "$WORK/pc" "$CKPT" "$FRAME0" > "$WORK/pose.txt" 2>"$WORK/pose.err"; then
        grep pose_iter_3 tests/agg_ref_courthouse0.txt > "$WORK/pose_ref.txt"
        grep pose_iter_3 "$WORK/pose.txt" > "$WORK/pose_iter3.txt"
        if out="$("$PYTORCH_PY" tests/cmp_dump.py "$WORK/pose_ref.txt" \
                  "$WORK/pose_iter3.txt" 1e-5)"; then
            ok "pose_enc after 4 refinement passes — $out"
            sed -n "s/^extrinsics/     extrinsics/p;s/^intrinsics/     intrinsics/p" \
                "$WORK/pose.txt" | cut -c1-100
        else
            bad "pose differs from the real model"; echo "$out"
        fi
    else
        bad "posecheck failed to run"; tail -4 "$WORK/pose.err"
    fi
fi

echo "[14/22] one DPT fusion block, on synthetic weights"
# Seconds, not the ~150 s the real head takes: resConfUnit2 -> bilinear
# upsample -> 1x1 out_conv against torch, so a fix to the fusion can be
# checked without a 909M-parameter transformer in front of it.
if [ -z "$PYTORCH_PY" ]; then
    skip "needs python + torch"
elif ! $NURL tests/fusecheck.nu "$WORK/fc" >/dev/null 2>"$WORK/fc_build.err"; then
    bad "fusecheck build"; tail -6 "$WORK/fc_build.err"
else
    "$WORK/fc" > "$WORK/fc.txt" 2>&1
    if grep -q "no gpukit backend" "$WORK/fc.txt"; then
        skip "no gpukit backend"
    else
        "$PYTORCH_PY" tests/fuse_oracle.py > "$WORK/fc_ref.txt" 2>&1
        if out="$("$PYTORCH_PY" tests/cmp_dump.py "$WORK/fc_ref.txt" "$WORK/fc.txt" 1e-4)"; then
            ok "resConfUnit2 + bilinear + out_conv — $out"
        else
            bad "fusion block differs from torch"; echo "$out"
        fi
    fi
fi

echo "[15/22] a DEPTH MAP and WORLD POINTS, end to end, vs the real model"
# preprocess -> DINOv2 -> aggregator -> DPT head -> depth + confidence
# at full frame resolution. ~150 s on top of the aggregator.
if [ ! -f "$CKPT" ] || [ ! -f "$FRAME0" ]; then
    skip "needs the checkpoint and an example frame"
elif [ -z "$PYTORCH_PY" ]; then
    skip "needs python to compare the dumps"
elif ! $NURL tests/depthcheck.nu "$WORK/dp" >/dev/null 2>"$WORK/dp_build.err"; then
    bad "depthcheck build"; tail -6 "$WORK/dp_build.err"
else
    if "$WORK/dp" "$CKPT" "$FRAME0" > "$WORK/depth.txt" 2>"$WORK/depth.err"; then
        grep -E "^(depth|depth_conf|world_points) " tests/agg_ref_courthouse0.txt \
            > "$WORK/depth_ref.txt"
        if out="$("$PYTORCH_PY" tests/cmp_dump.py "$WORK/depth_ref.txt" \
                  "$WORK/depth.txt" 1e-4)"; then
            ok "depth, confidence and unprojected world points — $out"
        else
            bad "depth differs from the real model"; echo "$out"
        fi
    else
        bad "depthcheck failed to run"; tail -4 "$WORK/depth.err"
    fi
fi

echo "[16/22] the CLI's front door — no checkpoint, no GPU, no network"
# Everything the command does BEFORE it loads a model: what it says when
# it has nothing to reconstruct, that a mistyped option is an error
# rather than a frame filename, that a directory of frames is found and
# sorted, and that a `/`-led --model that does not exist fails as a
# missing file instead of being looked up on Hugging Face. Seconds, and
# it needs none of the heavy inputs the rest of the suite does.
if ! $NURL src/main.nu "$WORK/lbm-cli" >/dev/null 2>"$WORK/cliarg.err"; then
    bad "CLI build"; tail -6 "$WORK/cliarg.err"
else
    cf=0
    # --help succeeds and shows an example; the usage alone is not help
    "$WORK/lbm-cli" --help > "$WORK/help.txt" 2>&1 || cf=$((cf+1))
    grep -q "^examples:" "$WORK/help.txt" || { bad "--help has no examples"; cf=$((cf+1)); }
    # --version must agree with the manifest. 0.4.0 shipped saying 0.3.0
    # because the two live in different files and nothing compared them.
    manifest_v=$(sed -n 's/^version = "\([^"]*\)".*/\1/p' nurl.toml | head -1)
    binary_v=$("$WORK/lbm-cli" --version 2>&1 | sed -n 's/^lingbot-map \(.*\)$/\1/p')
    if [ -z "$binary_v" ]; then
        bad "--version prints nothing recognisable"; cf=$((cf+1))
    elif [ "$binary_v" != "$manifest_v" ]; then
        bad "--version says $binary_v, nurl.toml says $manifest_v"; cf=$((cf+1))
    fi

    # each of these must fail, and must SAY what is wrong
    expect_msg() {  # <pattern> <args...>
        pat="$1"; shift
        if "$WORK/lbm-cli" "$@" > "$WORK/cliarg.txt" 2>&1; then
            bad "'$*' should have failed"; cf=$((cf+1))
        elif ! grep -qi "$pat" "$WORK/cliarg.txt"; then
            bad "'$*' did not mention '$pat': $(head -1 "$WORK/cliarg.txt")"
            cf=$((cf+1))
        fi
    }
    expect_msg "no frames"      # nothing at all
    expect_msg "no frames"      --model /nope/x.pt
    expect_msg "unknown option" --qiuet frame.png
    expect_msg "needs a value"  --out
    expect_msg "no such frame"  no-such-frame.png
    mkdir -p "$WORK/empty"
    expect_msg "no .png"        "$WORK/empty"    # a directory with no frames
    expect_msg "multiple of 14" --image-size 500 f.png
    expect_msg "multiple of 14" --image-size 0 f.png

    # A directory IS the frames — and the failure that follows must be
    # the missing local checkpoint, never a network lookup.
    if [ -d "$HOME/dev/lingbot-map/example/courthouse" ]; then
        expect_msg "no such file" --model /nope/x.pt --max-frames 2 \
            "$HOME/dev/lingbot-map/example/courthouse"

        # --max-frames then --stride, the order demo.py applies --first_k
        # and --stride in: 30 frames every 3rd is 10, not 90. The count is
        # printed before the checkpoint is opened, so this needs neither.
        "$WORK/lbm-cli" --model /nope/x.pt --max-frames 30 --stride 3 \
            "$HOME/dev/lingbot-map/example/courthouse" > "$WORK/stride.txt" 2>&1
        if ! grep -q "^frames 10 " "$WORK/stride.txt"; then
            bad "--max-frames 30 --stride 3 selected $(sed -n 's/^frames \([0-9]*\) .*/\1/p' "$WORK/stride.txt") frames, expected 10"
            cf=$((cf+1))
        fi
    fi
    [ "$cf" -eq 0 ] && ok "help, usage, unknown options, missing frames, dirs and --stride"
fi

echo "[17/22] the CLI, end to end, to a point-cloud file"
# One frame all the way through to a PLY a viewer can open. The numbers
# are already checked above; what this checks is that the program runs,
# that the header's vertex count matches the body it wrote (it is
# patched in afterwards, since the count is not known until the end),
# and that nothing non-finite reaches the file.
if [ ! -f "$CKPT" ] || [ ! -f "$FRAME0" ]; then
    skip "needs the checkpoint and an example frame"
elif ! $NURL src/main.nu "$WORK/lingbot-map" >/dev/null 2>"$WORK/cli_build.err"; then
    bad "CLI build"; tail -6 "$WORK/cli_build.err"
elif ! "$WORK/lingbot-map" --model "$CKPT" --out "$WORK/cloud.ply" --quiet \
        --ascii "$FRAME0" >"$WORK/cli.txt" 2>&1; then
    bad "CLI failed to run"; tail -4 "$WORK/cli.txt"
elif ! "$WORK/lingbot-map" --model "$CKPT" --out "$WORK/cloudb.ply" --quiet \
        "$FRAME0" >"$WORK/clib.txt" 2>&1; then
    bad "CLI failed to run (binary)"; tail -4 "$WORK/clib.txt"
else
    declared=$(sed -n "s/^element vertex 0*\([0-9][0-9]*\)$/\1/p" "$WORK/cloud.ply")
    body=$(sed "1,/^end_header$/d" "$WORK/cloud.ply" | grep -c .)
    nonfinite=$(sed "1,/^end_header$/d" "$WORK/cloud.ply" | grep -ci "nan\|inf" || true)
    # the default format is binary_little_endian: same count, and a body
    # of exactly 3 floats + 3 bytes per vertex
    bdeclared=$(sed -n "s/^element vertex 0*\([0-9][0-9]*\)$/\1/p" "$WORK/cloudb.ply")
    bhdr=$(head -c 512 "$WORK/cloudb.ply" | sed -n "1,/^end_header$/p" | wc -c)
    btotal=$(wc -c < "$WORK/cloudb.ply")
    bbody=$((btotal - bhdr))
    if [ -z "$declared" ]; then
        bad "no vertex count in the PLY header"
    elif [ "$declared" != "$body" ]; then
        bad "PLY header says $declared vertices, body has $body"
    elif [ "$declared" -lt 1000 ]; then
        bad "only $declared points — the confidence gate cannot be right"
    elif [ "$nonfinite" != "0" ]; then
        bad "$nonfinite non-finite coordinates in the cloud"
    elif [ "$bdeclared" != "$declared" ]; then
        bad "binary PLY has $bdeclared vertices, ASCII has $declared"
    elif [ "$bbody" != "$((declared * 15))" ]; then
        bad "binary body is $bbody bytes, expected $((declared * 15))"
    else
        ok "$declared points written, ASCII and binary agree"
    fi
fi

echo "[18/22] KV-cache eviction bookkeeping, 120 frames"
# A replay of the reference's own _apply_kv_cache_eviction_causal on
# frame indices. Checking eviction against the model itself would need
# 73+ frames through a 909M-parameter transformer on both sides; this
# checks what actually differs — which frames stay live, how many rows
# that is, and that nothing lands outside the cache.
if [ -z "$PY" ]; then
    skip "needs python"
elif ! $NURL tests/kvcheck.nu "$WORK/kv" >/dev/null 2>"$WORK/kv_build.err"; then
    bad "kvcheck build"; tail -6 "$WORK/kv_build.err"
else
    "$WORK/kv" > "$WORK/kv.txt" 2>&1
    "$PY" tests/kv_oracle.py > "$WORK/kv_ref.txt" 2>&1
    if out="$("$PY" tests/cmp_dump.py "$WORK/kv_ref.txt" "$WORK/kv.txt" 0)"; then
        ok "eviction matches the reference policy exactly — $out"
    else
        bad "eviction bookkeeping differs"; echo "$out"
    fi
fi

echo "[19/22] EVICTION against the real model, at a window that fits"
# The bookkeeping test above is indices; this one is activations. The
# window is shrunk to 1 + 2 on BOTH sides, so eviction bites at frame 3
# instead of frame 72 and six frames are enough. This is the test that
# caught the live set being one frame too wide.
if [ ! -f "$CKPT" ] || [ ! -f "$FRAME0" ]; then
    skip "needs the checkpoint and example frames"
elif [ -z "$PYTORCH_PY" ]; then
    skip "needs python to compare the dumps"
else
    EV=""
    for n in 000000 000001 000002 000003 000004 000005; do
        f="$(dirname "$FRAME0")/$n.png"
        [ -f "$f" ] && EV="$EV $f"
    done
    nev=$(echo $EV | wc -w)
    if [ "$nev" -lt 6 ]; then
        skip "needs six consecutive example frames, found $nev"
    elif ! $NURL tests/streamcheck.nu "$WORK/ev" >/dev/null 2>"$WORK/ev_build.err"; then
        bad "streamcheck build"; tail -6 "$WORK/ev_build.err"
    else
        LINGBOT_STREAM=1 LINGBOT_KV_SCALE=1 LINGBOT_KV_WINDOW=2 \
            "$PYTORCH_PY" tests/agg_oracle.py "$CKPT" $EV \
            > "$WORK/ev_ref.txt" 2>&1 &
        evpid=$!
        LINGBOT_KV_SCALE=1 LINGBOT_KV_WINDOW=2 "$WORK/ev" "$CKPT" $EV \
            > "$WORK/ev.txt" 2>"$WORK/ev.err"
        evrc=$?
        wait $evpid
        if [ "$evrc" != "0" ]; then
            bad "streamcheck failed to run"; tail -4 "$WORK/ev.err"
        elif grep "^stream" "$WORK/ev_ref.txt" > "$WORK/ev_ref_s.txt";
             grep "^stream" "$WORK/ev.txt" > "$WORK/ev_s.txt";
             out="$("$PYTORCH_PY" tests/cmp_dump.py \
                    "$WORK/ev_ref_s.txt" "$WORK/ev_s.txt" 1e-4)"; then
            ok "six frames, three of them past eviction — $out"
        else
            bad "eviction differs from the real model"; echo "$out"
        fi
    fi
fi


echo "[20/22] THE WHOLE DELIVERABLE vs the reference: same frames, same cloud"
# Every other step compares a module's activations on one or two frames.
# This one compares what the user actually gets — the point cloud — over a
# SEQUENCE, against ~/dev/lingbot-map driven through its own
# `inference_streaming`, and times both.
#
# It needs a CUDA torch, which `.venv-oracle` is NOT (it is a CPU build,
# deliberately — the rest of the suite only needs correctness). Set
# LINGBOT_CUDA_PY, or drop a CUDA venv at the repo root as `.venv-cuda`.
#
# `--scale-frames 1` drives the reference the way the port drives the
# model: every frame causal. demo.py's default is 8, which gives the first
# eight frames BIDIRECTIONAL attention as one block — a mode the port does
# not implement, and worth about 3% of the cloud. That is a known gap, not
# something this step can hide.
#
# The two thresholds are different questions. ONE frame is pure arithmetic
# and must agree tightly. A SEQUENCE accumulates f32 noise through the
# KV caches — the aggregator's and the camera head's — so its bound is
# looser. What it must NOT do is grow with sequence length: that was the
# pose-drift bug (the camera head ran cacheless, every frame posed alone),
# and after the fix the 20-frame median sits at ~2.4e-4 with the per-frame
# error flat from frame 2 to frame 20. The bound gives ~4x headroom.
if [ -n "${LINGBOT_CUDA_PY:-}" ]; then :;
elif [ -x "$REPO_ROOT/.venv-cuda/bin/python" ]; then LINGBOT_CUDA_PY="$REPO_ROOT/.venv-cuda/bin/python";
else LINGBOT_CUDA_PY=""; fi
CH="$HOME/dev/lingbot-map/example/courthouse"

if [ ! -f "$CKPT" ] || [ ! -d "$CH" ]; then
    skip "needs the checkpoint and ~/dev/lingbot-map/example/courthouse"
elif [ -z "$LINGBOT_CUDA_PY" ] || \
     ! CUDA_VISIBLE_DEVICES="${LINGBOT_CUDA_DEV:-0}" "$LINGBOT_CUDA_PY" \
         -c "import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
    skip "end-to-end differential — needs a CUDA torch (set LINGBOT_CUDA_PY)"
elif ! $NURL src/main.nu "$WORK/lbm-e2e" >/dev/null 2>"$WORK/e2e_build.err"; then
    bad "CLI build"; tail -6 "$WORK/e2e_build.err"
elif ! "$LINGBOT_CUDA_PY" -c "import scipy.spatial" 2>/dev/null; then
    skip "cloud comparison needs scipy"
else
    e2e_fail=0
    for N in 1 20; do
        FR=$(ls "$CH"/*.png 2>/dev/null | head -"$N")
        # shellcheck disable=SC2086
        if ! CUDA_VISIBLE_DEVICES="${LINGBOT_CUDA_DEV:-0}" PYTHONPATH="$HOME/dev/lingbot-map" \
                "$LINGBOT_CUDA_PY" tests/ref_cloud.py --scale-frames 1 \
                "$CKPT" "$WORK/ref$N.ply" $FR >/dev/null 2>"$WORK/ref$N.err"; then
            bad "the reference failed to run on $N frames"; tail -3 "$WORK/ref$N.err"
            e2e_fail=1; continue
        fi
        if ! "$WORK/lbm-e2e" --quiet --model "$CKPT" --max-frames "$N" \
                --out "$WORK/port$N.ply" "$CH" >"$WORK/port$N.log" 2>&1; then
            bad "the port failed to run on $N frames"; tail -3 "$WORK/port$N.log"
            e2e_fail=1; continue
        fi
        # 1 frame is arithmetic; 20 frames is arithmetic plus accumulation.
        [ "$N" = "1" ] && TOL=1e-4 || TOL=1e-3
        if out="$("$LINGBOT_CUDA_PY" tests/cmp_cloud.py \
                    "$WORK/ref$N.ply" "$WORK/port$N.ply" "$TOL" 2>&1)"; then
            ok "$N frame(s): $(echo "$out" | sed -n '2p')"
        else
            bad "$N frame(s) differ beyond $TOL"; echo "$out" | sed -n '1,3p'
            e2e_fail=1
        fi
        # Faster is half the requirement, so it is measured, not assumed.
        rs=$(sed -n 's/^ref_seconds \([0-9.]*\) .*/\1/p' "$WORK/ref$N.err")
        ps=$(sed -n 's/.*(\([0-9]*\) frames, \([0-9]*\) ms).*/\2/p' "$WORK/port$N.log")
        if [ -n "$rs" ] && [ -n "$ps" ]; then
            rms=$(awk -v r="$rs" 'BEGIN { printf "%d", r * 1000 }')
            echo "       $N frame(s): reference ${rs}s, port $((ps / 1000)).$((ps % 1000 / 100))s" \
                 "= $(awk -v r="$rms" -v p="$ps" 'BEGIN { printf "%.1fx", r / p }') faster"
            if [ "$ps" -ge "$rms" ]; then
                bad "$N frame(s): the port is NOT faster than the reference"
                e2e_fail=1
            fi
        fi
    done
fi

echo "[21/22] the VIEWER — serve a cloud and render it in a real browser"
# No checkpoint, no GPU, no torch: a synthetic PLY exercises the whole
# viewer path, and the path is what breaks. The page parses a binary PLY,
# uploads it and draws it; the failure that matters is a HUD that reports
# half a million points over an empty canvas, which looks identical to a
# working viewer from the DOM. tests/viewer_shot.sh counts lit pixels.
if ! $NURL src/main.nu "$WORK/lbm-view" >/dev/null 2>"$WORK/view_build.err"; then
    bad "CLI build"; tail -6 "$WORK/view_build.err"
else
    # a 3-axis cross of coloured points: asymmetric, so an axis swap or a
    # flipped up vector is visible, and small enough to render instantly
    "$PY" - "$WORK/synth.ply" <<'PLY' 2>/dev/null
import struct, sys
pts = []
for i in range(-60, 61):
    t = i / 60.0
    pts.append((t, 0.0, 0.0, 255, 60, 60))
    pts.append((0.0, t, 0.0, 60, 255, 60))
    pts.append((0.0, 0.0, t, 60, 60, 255))
for i in range(1200):                      # a slab so there is a body to see
    a = i * 0.0121
    pts.append((0.6 * (i % 40) / 40 - 0.3, 0.25 + 0.1 * ((i // 40) % 8),
                0.4 * ((a % 1.0) - 0.5), 200, 190, 170))
with open(sys.argv[1], "wb") as f:
    f.write(b"ply\nformat binary_little_endian 1.0\n")
    f.write(("element vertex %d\n" % len(pts)).encode())
    f.write(b"property float x\nproperty float y\nproperty float z\n"
            b"property uchar red\nproperty uchar green\nproperty uchar blue\n"
            b"end_header\n")
    for p in pts:
        f.write(struct.pack("<fffBBB", *p))
PLY
    if [ ! -s "$WORK/synth.ply" ]; then
        skip "viewer — needs python to write the test cloud"
    else
        VPORT="${LINGBOT_VIEW_PORT:-8791}"
        "$WORK/lbm-view" view "$WORK/synth.ply" --port "$VPORT" \
            >"$WORK/view.log" 2>&1 &
        VPID=$!
        # wait for the listener rather than sleeping a guess
        up=0; i=0
        while [ "$i" -lt 60 ]; do
            if curl -fsS -o /dev/null "http://127.0.0.1:$VPORT/" 2>/dev/null; then
                up=1; break
            fi
            i=$((i+1)); sleep 0.5
        done
        if [ "$up" != "1" ]; then
            bad "the viewer never came up on port $VPORT"; tail -3 "$WORK/view.log"
        else
            vf=0
            # the page, and the cloud byte-for-byte
            curl -fsS "http://127.0.0.1:$VPORT/" > "$WORK/page.html" 2>/dev/null \
                || { bad "GET / failed"; vf=1; }
            grep -q "lingbot-map viewer" "$WORK/page.html" \
                || { bad "GET / did not return the viewer page"; vf=1; }
            curl -fsS "http://127.0.0.1:$VPORT/cloud" > "$WORK/got.ply" 2>/dev/null \
                || { bad "GET /cloud failed"; vf=1; }
            cmp -s "$WORK/synth.ply" "$WORK/got.ply" \
                || { bad "/cloud did not serve the file verbatim"; vf=1; }

            # and then the part no amount of curl can check
            out="$(sh tests/viewer_shot.sh "http://127.0.0.1:$VPORT/?probe=6" \
                    "$WORK/shot.png" 2>"$WORK/shot.err")"
            rc=$?
            if [ "$rc" = "77" ]; then
                skip "the render check needs chrome or chromium on PATH"
                [ "$vf" -eq 0 ] && ok "page and cloud served correctly"
            elif [ "$rc" != "0" ]; then
                bad "the viewer drew nothing"; echo "$out"; tail -2 "$WORK/shot.err"
            else
                lit=$(echo "$out" | sed -n 's/^lit \([0-9]*\)\/.*/\1/p')
                # a few hundred lit pixels is a cross and a slab; zero is a
                # black canvas and the whole point of the check
                if [ "${lit:-0}" -lt 200 ]; then
                    bad "only $lit pixels drawn — the cloud is not on screen"
                    vf=1
                fi
                [ "$vf" -eq 0 ] && ok "served and rendered — $out"
            fi
        fi
        kill "$VPID" 2>/dev/null
        wait "$VPID" 2>/dev/null
    fi
fi

echo "[22/22] VIDEO input — an MJPEG AVI, parsed in pure NURL"
# No checkpoint, no GPU, no ffmpeg: tests/make_avi.py assembles the AVI
# with Pillow and struct, and the CLI's own extraction turns it back into
# frames. What is asserted: the fps arithmetic (12 fps source at --fps 6
# is every 2nd frame), the files landing on disk, and a re-extraction at
# another rate REPLACING the previous frames rather than mixing with them
# — the stale-tail bug every extractor grows sooner or later.
if ! $NURL src/main.nu "$WORK/lbm-vid" >/dev/null 2>"$WORK/vid_build.err"; then
    bad "CLI build"; tail -6 "$WORK/vid_build.err"
elif [ -z "$PYTORCH_PY" ] || ! "$PYTORCH_PY" -c "import PIL" 2>/dev/null; then
    skip "video fixture needs a python with Pillow (set PYTORCH_PY)"
else
    VFRAMES=""
    for n in 000000 000001 000002 000003 000004 000005; do
        pth="$HOME/dev/lingbot-map/example/courthouse/$n.png"
        [ -f "$pth" ] && VFRAMES="$VFRAMES $pth"
    done
    if [ -z "$VFRAMES" ]; then
        skip "video fixture needs the example frames"
    else
        # shellcheck disable=SC2086
        "$PYTORCH_PY" tests/make_avi.py "$WORK/walk.avi" 12 $VFRAMES >/dev/null 2>&1
        vf=0
        # 12 fps at --fps 6 = every 2nd of 6 frames = 3
        "$WORK/lbm-vid" --model /nope/x.pt --fps 6 "$WORK/walk.avi" \
            > "$WORK/vid.txt" 2>&1
        grep -q "^frames  3 extracted" "$WORK/vid.txt" \
            || { bad "--fps 6 of a 12 fps video should keep 3 of 6 frames"; \
                 head -3 "$WORK/vid.txt"; vf=1; }
        n=$(ls "$WORK"/walk_frames/*.jpg 2>/dev/null | wc -l)
        [ "$n" = "3" ] || { bad "expected 3 frame files, found $n"; vf=1; }
        # full rate replaces, never mixes
        "$WORK/lbm-vid" --quiet --model /nope/x.pt --fps 12 "$WORK/walk.avi" \
            >/dev/null 2>&1
        n=$(ls "$WORK"/walk_frames/*.jpg 2>/dev/null | wc -l)
        [ "$n" = "6" ] || { bad "re-extraction left $n files, expected exactly 6"; vf=1; }
        # the frames must be JPEGs our own decoder accepts (magic FF D8)
        m=$(head -c 2 "$WORK/walk_frames/000000.jpg" | od -An -tu1 | tr -s " ")
        [ "$m" = " 255 216" ] || { bad "extracted frame is not a JPEG ($m)"; vf=1; }
        [ "$vf" -eq 0 ] && ok "AVI parsed, fps stride right, re-extraction replaces"
    fi
fi

echo
echo "lingbot-map: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
