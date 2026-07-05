#!/usr/bin/env bash
# ============================================================
#  tests/image_test.sh — build tests/roundtrip.nu and check the codecs
#  against Pillow: for RGB / RGBA / grayscale / 8-bit-palette PNGs, decode
#  with NURL, re-encode to PNG and PPM, and assert Pillow reads back exactly
#  the reference pixels. Pillow saves with adaptive filtering, so the decode
#  path exercises all five scanline filters. Re-runs under AddressSanitizer.
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

if ! python3 -c "import PIL" 2>/dev/null; then
    echo "  (skipped — python3 + Pillow not available)"; exit 0
fi

WORK="$(mktemp -d -t image-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/3] build tests/roundtrip.nu"
if ! $NURL tests/roundtrip.nu "$WORK/roundtrip" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build roundtrip:"; tail -8 "$WORK/build.err"; exit 1
fi

echo "[2/3] generate reference images"
python3 - "$WORK" <<'PY'
import sys; from PIL import Image
W=sys.argv[1]
def fill(im,mode):
    px=im.load(); w,h=im.size
    for y in range(h):
        for x in range(w):
            if   mode=="RGB":  px[x,y]=(x*7%256,y*11%256,(x*y)%256)
            elif mode=="RGBA": px[x,y]=(x*7%256,y*11%256,(x+y)%256,(x*13)%256)
            elif mode=="L":    px[x,y]=(x*3+y*5)%256
for name,mode in (("rgb","RGB"),("rgba","RGBA"),("gray","L")):
    im=Image.new(mode,(37,29)); fill(im,mode); im.save(f"{W}/{name}.png", optimize=True)
# 8-bit palette (explicit palette, no optimize keeps depth 8)
im=Image.new("P",(40,24)); pal=[]
for i in range(256): pal+=[(i*7)%256,(i*13)%256,(i*29)%256]
im.putpalette(pal); px=im.load()
for y in range(24):
    for x in range(40): px[x,y]=(x*3+y*5)%200
im.save(f"{W}/pal.png")
PY

echo "[3/3] round-trip + verify"
PASS=0; FAIL=0
for n in rgb rgba gray pal; do
    "$WORK/roundtrip" "$WORK/$n.png" "$WORK/$n.out.png" "$WORK/$n.out.ppm" >/dev/null 2>&1
done
python3 - "$WORK" <<'PY'
import sys; from PIL import Image
W=sys.argv[1]; p=f=0
for n in ("rgb","rgba","gray","pal"):
    ref=Image.open(f"{W}/{n}.png").convert("RGBA")
    try:
        opng=Image.open(f"{W}/{n}.out.png").convert("RGBA")
        oppm=Image.open(f"{W}/{n}.out.ppm").convert("RGB")
    except Exception as e:
        print(f"  FAIL {n}: {e}"); f+=1; continue
    if list(ref.getdata())==list(opng.getdata()): print(f"  PASS {n}: decode→encode PNG == reference"); p+=1
    else: print(f"  FAIL {n}: PNG pixels differ"); f+=1
    if list(ref.convert('RGB').getdata())==list(oppm.getdata()): print(f"  PASS {n}: decode→PPM == reference"); p+=1
    else: print(f"  FAIL {n}: PPM pixels differ"); f+=1
print(f"RESULT {p} {f}")
sys.exit(1 if f else 0)
PY
V=$?

echo "[asan] re-run decode/encode under AddressSanitizer"
if NURL_SAN=1 $NURL tests/roundtrip.nu "$WORK/rt_san" >/dev/null 2>"$WORK/san_build.err"; then
    SAN_OK=1
    for n in rgb rgba gray pal; do
        "$WORK/rt_san" "$WORK/$n.png" "$WORK/s.png" "$WORK/s.ppm" >/dev/null 2>"$WORK/san.out" || true
        grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/san.out" && SAN_OK=0
    done
    [ "$SAN_OK" = 1 ] && echo "  PASS ASan clean (all cases)" || { echo "  FAIL ASan"; V=1; }
else
    echo "  (skipped ASan build)"
fi

[ "$V" = 0 ] && echo "== image tests: PASS" || echo "== image tests: FAIL"
exit $V
