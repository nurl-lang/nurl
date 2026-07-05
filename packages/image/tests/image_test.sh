#!/usr/bin/env bash
# ============================================================
#  tests/image_test.sh — build tests/roundtrip.nu and check the codecs
#  against Pillow.
#    PNG/PPM (lossless): decode → re-encode → assert pixel-exact.
#    JPEG (lossy): decode → assert within an IDCT/upsampling tolerance of
#      Pillow's own decode (4:4:4 / 4:2:0 / greyscale).
#  Then re-runs the decode/encode paths under AddressSanitizer.
#
#  Run from the package dir:  ./tests/image_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
#  Skips cleanly if python3 + Pillow are not installed.
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t image-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[ops] build + run tests/ops.nu (deterministic, no references)"
if ! $NURL tests/ops.nu "$WORK/ops" >/dev/null 2>"$WORK/ops_build.err"; then
    echo "FAIL: could not build ops:"; tail -8 "$WORK/ops_build.err"; exit 1
fi
if ! "$WORK/ops" | sed 's/^/  /'; then echo "== image tests: FAIL"; exit 1; fi
if NURL_SAN=1 $NURL tests/ops.nu "$WORK/ops_san" >/dev/null 2>&1; then
    if "$WORK/ops_san" >"$WORK/ops_san.out" 2>&1 && ! grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/ops_san.out"; then
        echo "  PASS ops ASan clean"
    else
        echo "  FAIL ops under ASan"; tail -5 "$WORK/ops_san.out"; exit 1
    fi
fi

if ! python3 -c "import PIL, numpy" 2>/dev/null; then
    echo "  (codec reference checks skipped — python3 + Pillow + numpy not available)"; exit 0
fi

echo "[1/5] build tests/roundtrip.nu + tests/jpegenc.nu"
if ! $NURL tests/jpegenc.nu "$WORK/jpegenc" >/dev/null 2>"$WORK/jbuild.err"; then
    echo "FAIL: could not build jpegenc:"; tail -8 "$WORK/jbuild.err"; exit 1
fi
if ! $NURL tests/roundtrip.nu "$WORK/roundtrip" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build roundtrip:"; tail -8 "$WORK/build.err"; exit 1
fi

echo "[2/5] generate references"
python3 - "$WORK" <<'PY'
import sys, numpy as np; from PIL import Image
W=sys.argv[1]
def fill(im,mode):
    px=im.load(); w,h=im.size
    for y in range(h):
        for x in range(w):
            if   mode=="RGB":  px[x,y]=(x*7%256,y*11%256,(x*y)%256)
            elif mode=="RGBA": px[x,y]=(x*7%256,y*11%256,(x+y)%256,(x*13)%256)
            elif mode=="L":    px[x,y]=(x*3+y*5)%256
# PNG (lossless)
for name,mode in (("rgb","RGB"),("rgba","RGBA"),("gray","L")):
    im=Image.new(mode,(37,29)); fill(im,mode); im.save(f"{W}/{name}.png", optimize=True)
im=Image.new("P",(40,24)); pal=[]
for i in range(256): pal+=[(i*7)%256,(i*13)%256,(i*29)%256]
im.putpalette(pal); px=im.load()
for y in range(24):
    for x in range(40): px[x,y]=(x*3+y*5)%200
im.save(f"{W}/pal.png")
# JPEG (lossy) — smooth gradients so chroma has no artificial sharp edges
h,w=48,64
a=np.zeros((h,w,3),dtype=np.uint8)
for y in range(h):
    for x in range(w): a[y,x]=[x*255//w, y*255//h, (x+y)*255//(w+h)]
Image.fromarray(a,"RGB").save(f"{W}/j444.jpg", quality=92, subsampling=0)
Image.fromarray(a,"RGB").save(f"{W}/j420.jpg", quality=92, subsampling=2)
Image.fromarray(a,"RGB").save(f"{W}/p444.jpg", quality=92, subsampling=0, progressive=True)
Image.fromarray(a,"RGB").save(f"{W}/p420.jpg", quality=92, subsampling=2, progressive=True)
g=np.zeros((h,w),dtype=np.uint8)
for y in range(h):
    for x in range(w): g[y,x]=(x*4+y*3)%256
Image.fromarray(g,"L").save(f"{W}/jgray.jpg", quality=92)
Image.fromarray(g,"L").save(f"{W}/pgray.jpg", quality=92, progressive=True)
# odd-size progressive with restart markers — exercises non-interleaved AC
# scans whose block raster is narrower than the padded MCU grid
rng=np.random.default_rng(3)
Image.fromarray((rng.random((29,37,3))*255).astype(np.uint8),"RGB").save(
    f"{W}/pnoise.jpg", quality=85, subsampling=0, progressive=True, restart_marker_blocks=2)
PY

echo "[3/5] PNG/PPM round-trip (pixel-exact)"
for n in rgb rgba gray pal; do
    "$WORK/roundtrip" "$WORK/$n.png" "$WORK/$n.out.png" "$WORK/$n.out.ppm" >/dev/null 2>&1
done
python3 - "$WORK" <<'PY'
import sys; from PIL import Image
W=sys.argv[1]; f=0
for n in ("rgb","rgba","gray","pal"):
    ref=Image.open(f"{W}/{n}.png").convert("RGBA")
    try:
        opng=Image.open(f"{W}/{n}.out.png").convert("RGBA"); oppm=Image.open(f"{W}/{n}.out.ppm").convert("RGB")
    except Exception as e: print(f"  FAIL {n}: {e}"); f+=1; continue
    print(f"  {'PASS' if list(ref.getdata())==list(opng.getdata()) else 'FAIL'} {n}: decode→encode PNG"); f+= list(ref.getdata())!=list(opng.getdata())
    print(f"  {'PASS' if list(ref.convert('RGB').getdata())==list(oppm.getdata()) else 'FAIL'} {n}: decode→PPM");  f+= list(ref.convert('RGB').getdata())!=list(oppm.getdata())
sys.exit(1 if f else 0)
PY
V=$?

echo "[3b/5] PNG feature matrix (bit depths, 16-bit, tRNS, Adam7 — pixel-exact)"
mkdir -p "$WORK/pm"
python3 tests/png_matrix.py gen "$WORK/pm"
for n in $(cat "$WORK/pm/cases.txt"); do
    "$WORK/roundtrip" "$WORK/pm/$n.png" "$WORK/pm/$n.out.png" "$WORK/pm/$n.out.ppm" >/dev/null 2>&1 || true
done
python3 tests/png_matrix.py check "$WORK/pm" || V=1

echo "[4/5] JPEG decode, baseline + progressive (within tolerance of Pillow)"
for n in j444 j420 jgray p444 p420 pgray pnoise; do
    "$WORK/roundtrip" "$WORK/$n.jpg" "$WORK/$n.d.png" "$WORK/$n.out.ppm" >/dev/null 2>&1
done
python3 - "$WORK" <<'PY'
import sys, numpy as np; from PIL import Image
W=sys.argv[1]; f=0
# (name, max-abs-diff tolerance) — 4:4:4/grey = IDCT rounding, 4:2:0 = box upsample
for n,tol in (("j444",3),("j420",12),("jgray",3),("p444",3),("p420",12),("pgray",3),("pnoise",3)):
    ref=np.asarray(Image.open(f"{W}/{n}.jpg").convert("RGB"),dtype=int)
    ours=np.asarray(Image.open(f"{W}/{n}.out.ppm").convert("RGB"),dtype=int)
    if ref.shape!=ours.shape: print(f"  FAIL {n}: shape {ref.shape} vs {ours.shape}"); f+=1; continue
    d=int(np.abs(ref-ours).max()); m=float(np.abs(ref-ours).mean())
    ok = d<=tol
    print(f"  {'PASS' if ok else 'FAIL'} {n}: max_diff={d} (≤{tol}) mean={m:.3f}"); f += (0 if ok else 1)
sys.exit(1 if f else 0)
PY
[ $? = 0 ] || V=1

echo "[5/5] JPEG encode (444/420/422/gray; self-decode + Pillow re-decode)"
python3 - "$WORK" <<'PY'
import sys, numpy as np; from PIL import Image
W=sys.argv[1]
h,w=48,64
a=np.zeros((h,w,3),dtype=np.uint8)
for y in range(h):
    for x in range(w): a[y,x]=[x*255//w, y*255//h, (x+y)*255//(w+h)]
Image.fromarray(a,"RGB").save(f"{W}/grad.png")
rng=np.random.default_rng(7)
Image.fromarray((rng.random((29,37,3))*255).astype(np.uint8),"RGB").save(f"{W}/noise.png")
PY
if ! "$WORK/jpegenc" "$WORK/grad.png" "$WORK/e444.jpg" "$WORK/e420.jpg" "$WORK/e422.jpg" "$WORK/egray.jpg" | sed 's/^/  /'; then
    echo "  FAIL jpegenc (smooth)"; V=1
fi
# odd-size noise: structural health only (chroma subsampling loss is inherent)
if ! "$WORK/jpegenc" "$WORK/noise.png" "$WORK/x1.jpg" "$WORK/x2.jpg" "$WORK/x3.jpg" "$WORK/x4.jpg" loose >/dev/null; then
    echo "  FAIL jpegenc (odd-size noise)"; V=1
fi
python3 - "$WORK" <<'PY'
import sys, numpy as np; from PIL import Image
W=sys.argv[1]; f=0
src=np.asarray(Image.open(f"{W}/grad.png").convert("RGB"),dtype=int)
for n,tol in (("e444",6),("e420",12),("e422",12)):
    im=Image.open(f"{W}/{n}.jpg"); im.load()
    d=int(np.abs(np.asarray(im.convert("RGB"),dtype=int)-src).max())
    ok=d<=tol
    print(f"  {'PASS' if ok else 'FAIL'} {n}: Pillow re-decode max_diff={d} (≤{tol})"); f+=0 if ok else 1
g=Image.open(f"{W}/egray.jpg"); g.load()
gs=np.asarray(Image.open(f"{W}/grad.png").convert("L"),dtype=int)
d=int(np.abs(np.asarray(g.convert("L"),dtype=int)-gs).max())
ok=d<=6
print(f"  {'PASS' if ok else 'FAIL'} egray: Pillow re-decode max_diff={d} (≤6)"); f+=0 if ok else 1
for n in ("x1","x2","x3","x4"):
    try: im=Image.open(f"{W}/{n}.jpg"); im.load()
    except Exception as e: print(f"  FAIL {n}: {e}"); f+=1
sys.exit(1 if f else 0)
PY
[ $? = 0 ] || V=1

echo "[fuzz] truncation + mutation sweeps over every decoder"
if ! $NURL tests/fuzz.nu "$WORK/fuzz" >/dev/null 2>"$WORK/fbuild.err"; then
    echo "FAIL: could not build fuzz:"; tail -8 "$WORK/fbuild.err"; V=1
else
    "$WORK/roundtrip" "$WORK/pm/pal4.png" "$WORK/pm/tmp.png" "$WORK/seed.ppm" >/dev/null 2>&1
    FUZZ_OK=1
    for f in pm/adam_rgba16.png pm/paltrns.png pm/g1.png j420.jpg p420.jpg seed.ppm; do
        if ! timeout 120 "$WORK/fuzz" "$WORK/$f" >/dev/null 2>&1; then
            echo "  FAIL fuzz (native): $f"; FUZZ_OK=0
        fi
    done
    if NURL_SAN=1 $NURL tests/fuzz.nu "$WORK/fuzz_san" >/dev/null 2>&1; then
        for f in pm/adam_rgba16.png j420.jpg p420.jpg; do
            timeout 600 "$WORK/fuzz_san" "$WORK/$f" >"$WORK/fsan.out" 2>&1 || FUZZ_OK=0
            grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/fsan.out" && { echo "  FAIL fuzz ASan: $f"; FUZZ_OK=0; }
        done
    fi
    [ "$FUZZ_OK" = 1 ] && echo "  PASS fuzz (6 seeds native, 3 under ASan — no crash/hang/leak)" || V=1
fi

echo "[asan] decode/encode under AddressSanitizer"
if NURL_SAN=1 $NURL tests/roundtrip.nu "$WORK/rt_san" >/dev/null 2>"$WORK/san_build.err"; then
    SAN_OK=1
    for f in rgb.png rgba.png gray.png pal.png pm/adam_rgba16.png pm/paltrns.png pm/g1.png j444.jpg j420.jpg jgray.jpg p444.jpg p420.jpg pgray.jpg pnoise.jpg; do
        "$WORK/rt_san" "$WORK/$f" "$WORK/s.png" "$WORK/s.ppm" >/dev/null 2>"$WORK/san.out" || true
        grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/san.out" && SAN_OK=0
    done
    if NURL_SAN=1 $NURL tests/jpegenc.nu "$WORK/jpegenc_san" >/dev/null 2>&1; then
        "$WORK/jpegenc_san" "$WORK/noise.png" "$WORK/sa.jpg" "$WORK/sb.jpg" "$WORK/sc.jpg" "$WORK/sd.jpg" loose >"$WORK/jsan.out" 2>&1 || SAN_OK=0
        grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/jsan.out" && SAN_OK=0
    fi
    [ "$SAN_OK" = 1 ] && echo "  PASS ASan clean (all cases)" || { echo "  FAIL ASan"; V=1; }
else
    echo "  (skipped ASan build)"
fi

[ "$V" = 0 ] && echo "== image tests: PASS" || echo "== image tests: FAIL"
exit $V
