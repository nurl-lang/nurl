#!/bin/sh
# ============================================================
#  viewer_shot.sh — render the viewer headlessly and report what
#  the GPU actually drew.
#
#    ./tests/viewer_shot.sh <viewer-url> [out.png] [WxH]
#
#  e.g.  ./tests/viewer_shot.sh 'http://127.0.0.1:8730/?probe=6' shot.png
#
#  Chrome's own --screenshot grabs a compositor frame that can predate
#  the WebGL draw — it will happily hand back the loading screen of a
#  page that has long since finished. --dump-dom always reflects the
#  settled page, so the viewer's ?probe=N mode renders N frames, reads
#  the framebuffer back with gl.readPixels and writes the frame into
#  the DOM as a data URL. This pulls that out.
#
#  Prints "lit <n>/<total> mean <r,g,b> points <n>" and writes the PNG.
#  Exits non-zero when nothing was drawn, which is the failure that
#  matters: a viewer can report half a million points in its HUD and
#  render an empty canvas, and the two look identical from the DOM.
# ============================================================
set -u
URL="${1:?usage: viewer_shot.sh <url> [out.png]}"
OUT="${2:-}"
SIZE="${3:-1280,800}"

CHROME=""
for c in google-chrome chromium chromium-browser; do
    command -v "$c" >/dev/null 2>&1 && { CHROME="$c"; break; }
done
[ -n "$CHROME" ] || { echo "viewer_shot: no chrome/chromium on PATH" >&2; exit 77; }

DOM="$(mktemp)"; trap 'rm -f "$DOM"' EXIT
# SwiftShader: these machines have no GPU wired into headless chrome, and
# the point of the check is the draw path, not the driver.
"$CHROME" --headless --disable-gpu --enable-unsafe-swiftshader --no-sandbox \
    --virtual-time-budget=120000 --run-all-compositor-stages-before-draw \
    --window-size="$SIZE" \
    --dump-dom "$URL" > "$DOM" 2>/dev/null

LIT=$(sed -n 's/.*id="probe" data-lit="\([0-9]*\)".*/\1/p' "$DOM" | head -1)
TOT=$(sed -n 's/.*data-total="\([0-9]*\)".*/\1/p' "$DOM" | head -1)
MEAN=$(sed -n 's/.*data-mean="\([0-9,]*\)".*/\1/p' "$DOM" | head -1)
PTS=$(sed -n 's/.*data-points="\([0-9]*\)".*/\1/p' "$DOM" | head -1)

if [ -z "$LIT" ]; then
    echo "viewer_shot: the page never reached the probe" >&2
    sed -n 's/.*id="stat"[^>]*>\([^<]*\)<.*/  page said: \1/p' "$DOM" | head -2 >&2
    exit 1
fi

if [ -n "$OUT" ]; then
    # the data URL is the element's text; strip the prefix and decode
    sed -n 's/.*id="probe"[^>]*>data:image\/png;base64,\([A-Za-z0-9+/=]*\)<.*/\1/p' \
        "$DOM" | head -1 | base64 -d > "$OUT" 2>/dev/null
    [ -s "$OUT" ] || echo "viewer_shot: could not decode the frame into $OUT" >&2
fi

echo "lit $LIT/$TOT mean $MEAN points $PTS"
[ "$LIT" -gt 0 ] || { echo "viewer_shot: nothing was drawn" >&2; exit 1; }
