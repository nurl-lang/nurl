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

if ! python3 -c "import PIL, numpy" 2>/dev/null; then
    echo "  (skipped — python3 + Pillow + numpy not available)"; exit 0
fi

WORK="$(mktemp -d -t image-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/4] build tests/roundtrip.nu"
if ! $NURL tests/roundtrip.nu "$WORK/roundtrip" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build roundtrip:"; tail -8 "$WORK/build.err"; exit 1
fi

echo "[2/4] generate references"
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
g=np.zeros((h,w),dtype=np.uint8)
for y in range(h):
    for x in range(w): g[y,x]=(x*4+y*3)%256
Image.fromarray(g,"L").save(f"{W}/jgray.jpg", quality=92)
PY

echo "[3/4] PNG/PPM round-trip (pixel-exact)"
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

echo "[4/4] JPEG decode (within tolerance of Pillow)"
for n in j444 j420 jgray; do
    "$WORK/roundtrip" "$WORK/$n.jpg" "$WORK/$n.d.png" "$WORK/$n.out.ppm" >/dev/null 2>&1
done
python3 - "$WORK" <<'PY'
import sys, numpy as np; from PIL import Image
W=sys.argv[1]; f=0
# (name, max-abs-diff tolerance) — 4:4:4/grey = IDCT rounding, 4:2:0 = box upsample
for n,tol in (("j444",3),("j420",12),("jgray",3)):
    ref=np.asarray(Image.open(f"{W}/{n}.jpg").convert("RGB"),dtype=int)
    ours=np.asarray(Image.open(f"{W}/{n}.out.ppm").convert("RGB"),dtype=int)
    if ref.shape!=ours.shape: print(f"  FAIL {n}: shape {ref.shape} vs {ours.shape}"); f+=1; continue
    d=int(np.abs(ref-ours).max()); m=float(np.abs(ref-ours).mean())
    ok = d<=tol
    print(f"  {'PASS' if ok else 'FAIL'} {n}: max_diff={d} (≤{tol}) mean={m:.3f}"); f += (0 if ok else 1)
sys.exit(1 if f else 0)
PY
[ $? = 0 ] || V=1

echo "[asan] decode/encode under AddressSanitizer"
if NURL_SAN=1 $NURL tests/roundtrip.nu "$WORK/rt_san" >/dev/null 2>"$WORK/san_build.err"; then
    SAN_OK=1
    for f in rgb.png rgba.png gray.png pal.png j444.jpg j420.jpg jgray.jpg; do
        "$WORK/rt_san" "$WORK/$f" "$WORK/s.png" "$WORK/s.ppm" >/dev/null 2>"$WORK/san.out" || true
        grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/san.out" && SAN_OK=0
    done
    [ "$SAN_OK" = 1 ] && echo "  PASS ASan clean (all cases)" || { echo "  FAIL ASan"; V=1; }
else
    echo "  (skipped ASan build)"
fi

[ "$V" = 0 ] && echo "== image tests: PASS" || echo "== image tests: FAIL"
exit $V
