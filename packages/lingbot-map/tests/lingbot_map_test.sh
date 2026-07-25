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

echo "[1/17] camera geometry vs the reference torch code"
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

echo "[2/17] frame preprocessing vs the reference load_fn pipeline"
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

echo "[3/17] position-grid resample vs torch bicubic+antialias"
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

echo "[4/17] 2-D rotary position embedding vs the reference"
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

echo "[5/17] patch embedding vs torch Conv2d"
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

echo "[6/17] full transformer block vs the reference Block"
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
echo "[7/17] the real 4.6 GB checkpoint (skipped when absent)"
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

echo "[8/17] the block on the DEVICE (f32) vs the host reference"
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

echo "[9/17] 3-D rope vs the real WanRotaryPosEmbed"
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

echo "[10/17] the DINOv2 trunk on a real frame vs the real model"
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

echo "[11/17] the WHOLE aggregator on a real frame vs the real model"
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
            if out="$("$PYTORCH_PY" tests/cmp_dump.py tests/agg_ref_courthouse0.txt \
                      <(grep agg_out "$WORK/agg.txt") 1e-5)"; then
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

echo "[12/17] two frames STREAMED through the KV cache"
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

echo "[13/17] a camera POSE, end to end, vs the real model"
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
        if out="$("$PYTORCH_PY" tests/cmp_dump.py "$WORK/pose_ref.txt" \
                  <(grep pose_iter_3 "$WORK/pose.txt") 1e-5)"; then
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

echo "[14/17] one DPT fusion block, on synthetic weights"
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

echo "[15/17] a DEPTH MAP and WORLD POINTS, end to end, vs the real model"
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

echo "[16/17] the CLI, end to end, to a point-cloud file"
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
        "$FRAME0" >"$WORK/cli.txt" 2>&1; then
    bad "CLI failed to run"; tail -4 "$WORK/cli.txt"
else
    declared=$(sed -n "s/^element vertex 0*\([0-9][0-9]*\)$/\1/p" "$WORK/cloud.ply")
    body=$(sed "1,/^end_header$/d" "$WORK/cloud.ply" | grep -c .)
    nonfinite=$(sed "1,/^end_header$/d" "$WORK/cloud.ply" | grep -ci "nan\|inf" || true)
    if [ -z "$declared" ]; then
        bad "no vertex count in the PLY header"
    elif [ "$declared" != "$body" ]; then
        bad "PLY header says $declared vertices, body has $body"
    elif [ "$declared" -lt 1000 ]; then
        bad "only $declared points — the confidence gate cannot be right"
    elif [ "$nonfinite" != "0" ]; then
        bad "$nonfinite non-finite coordinates in the cloud"
    else
        ok "$declared points written, header and body agree"
    fi
fi

echo "[17/17] KV-cache eviction bookkeeping, 120 frames"
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

echo
echo "lingbot-map: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
