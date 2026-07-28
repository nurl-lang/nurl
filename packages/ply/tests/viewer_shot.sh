#!/bin/sh
# ============================================================
#  viewer_shot.sh — render the viewer headlessly and report what
#  the GPU actually drew.
#
#    ./tests/viewer_shot.sh <viewer-url> [out.png] [WxH]
#
#  e.g.  ./tests/viewer_shot.sh 'http://127.0.0.1:8730/?probe=6' shot.png
#
#  This asks a narrower question than `--screenshot` does: what did the
#  GPU actually draw, independent of anything the DOM is painting over
#  it. The viewer's ?probe=N mode renders N frames, reads the framebuffer
#  back with gl.readPixels and writes it into the DOM as a data URL;
#  --dump-dom pulls it out.
#
#  Worth the separation: for a while this viewer rendered perfectly and
#  showed the user a loading overlay that never went away, and a
#  screenshot cannot tell those two apart.
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

# The probe reads the GL canvas and is blind to the DOM stacked on top of
# it, so a second pass photographs the WHOLE PAGE and checks the loading
# overlay actually went away. That is not hypothetical: 0.4.x shipped
# rendering perfectly behind an overlay that never left, and every
# canvas-level check passed the entire time.
OVER=$(sed -n 's/.*data-overlay="\([^"]*\)".*/\1/p' "$DOM" | head -1)
if [ "$OVER" != "none" ]; then
    echo "viewer_shot: the loading overlay is still VISIBLE (display: $OVER)" >&2
    echo "lit $LIT/$TOT mean $MEAN points $PTS"
    exit 1
fi

echo "lit $LIT/$TOT mean $MEAN points $PTS"
[ "$LIT" -gt 0 ] || { echo "viewer_shot: nothing was drawn" >&2; exit 1; }
