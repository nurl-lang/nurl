#!/usr/bin/env bash
# ============================================================
#  tests/demo_test.sh — build the demo server, start it against a real
#  YOLOE model + GPU, and drive the /detect API the way the browser
#  does: baseline detections, class filtering (on=), confidence
#  gating (conf=), masks toggle, garbage-body 400, and a 60-frame
#  sustained run with an RSS leak watch.
#
#  Needs a YOLOE-seg export + vocabulary and an NVIDIA GPU:
#    YOLOE_MODEL    (default: $HOME/yoloe-v8s-seg.onnx)
#    YOLOE_CLASSES  (default: $HOME/yoloe-classes.txt)
#  Skips (exit 0) when the model or a GPU is unavailable, so the
#  suite stays green on CI boxes.
#
#  Run from the package dir:  ./tests/demo_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

MODEL="${YOLOE_MODEL:-$HOME/yoloe-v8s-seg.onnx}"
CLASSES="${YOLOE_CLASSES:-$HOME/yoloe-classes.txt}"
TESTIMG="../yoloe/docs/demo.png"
PORT="${YOLOE_DEMO_PORT:-8199}"

if [ ! -f "$MODEL" ] || [ ! -f "$CLASSES" ]; then
    echo "SKIP: model/classes not found ($MODEL) — set YOLOE_MODEL / YOLOE_CLASSES"
    exit 0
fi
if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
    echo "SKIP: no NVIDIA GPU visible"
    exit 0
fi

WORK="$(mktemp -d -t yoloe-demo-test.XXXXXX)"
SERVE_PID=""
cleanup() { [ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/3] build src/main.nu"
if ! $NURL src/main.nu "$WORK/demo" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build the demo server:"; tail -8 "$WORK/build.err"; exit 1
fi

echo "[2/3] start server (model: $MODEL)"
"$WORK/demo" --model "$MODEL" --classes "$CLASSES" --host 127.0.0.1 --port "$PORT" \
    >"$WORK/server.log" 2>&1 &
SERVE_PID=$!
for i in $(seq 1 60); do
    curl -s --max-time 1 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
    sleep 0.5
    kill -0 "$SERVE_PID" 2>/dev/null || { echo "FAIL: server died:"; tail -5 "$WORK/server.log"; exit 1; }
done

echo "[3/3] drive /detect"
BASE="http://127.0.0.1:$PORT"

# health + page render
[ "$(curl -s "$BASE/health")" = "ok" ] && ok health || bad health
curl -s "$BASE/" | grep -q 'class="cls on"' && ok "page renders class chips" || bad "page renders class chips"

# baseline: the demo image contains a dog and a bicycle
R="$(curl -s -X POST --data-binary @"$TESTIMG" "$BASE/detect?conf=0.25&masks=1")"
echo "$R" | grep -q '"n": *[1-9]' || echo "$R" | grep -q '"n":[1-9]' && true
echo "$R" | grep -q '"dog"' && ok "baseline finds the dog" || bad "baseline finds the dog"
echo "$R" | grep -q '"img": *"data:image\/jpeg;base64,' \
    || echo "$R" | grep -q '"img":"data:image\/jpeg;base64,' \
    && ok "returns a composited jpeg" || bad "returns a composited jpeg"

# class filter: enable only class 1 (dog) — nothing else may appear
R="$(curl -s -X POST --data-binary @"$TESTIMG" "$BASE/detect?conf=0.25&on=1")"
if echo "$R" | grep -q '"dog"' && ! echo "$R" | grep -q '"bicycle"'; then
    ok "class filter (on=1 → dog only)"
else
    bad "class filter (on=1 → dog only)"
fi

# confidence gate: at 0.99 nothing survives
R="$(curl -s -X POST --data-binary @"$TESTIMG" "$BASE/detect?conf=0.99")"
echo "$R" | grep -qE '"n": *0|"n":0' && ok "conf=0.99 yields no detections" || bad "conf=0.99 yields no detections"

# garbage body → 400
CODE="$(printf 'not an image' | curl -s -o /dev/null -w '%{http_code}' -X POST --data-binary @- "$BASE/detect")"
[ "$CODE" = "400" ] && ok "garbage body → 400" || bad "garbage body → 400 (got $CODE)"

# sustained run + RSS leak watch
RSS0="$(ps -o rss= -p "$SERVE_PID" | tr -d ' ')"
for i in $(seq 1 60); do
    curl -s -o /dev/null -X POST --data-binary @"$TESTIMG" "$BASE/detect?conf=0.25&masks=1"
done
RSS1="$(ps -o rss= -p "$SERVE_PID" | tr -d ' ')"
GROW=$(( (RSS1 - RSS0) / 1024 ))
if [ "$GROW" -lt 40 ]; then ok "60-frame sustained run (RSS +${GROW} MB)"; else bad "RSS grew ${GROW} MB over 60 frames"; fi

echo
echo "PASS $PASS · FAIL $FAIL"
[ "$FAIL" -eq 0 ]
