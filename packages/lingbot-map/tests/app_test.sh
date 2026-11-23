#!/bin/sh
# What `lingbot-map serve` adds to recon-kit's service (whose own test,
# packages/recon-kit/tests/serve_test.sh, covers the routes, uploads, the
# job lifecycle and 3-D objects): the page shows this model's options, and
# a start request becomes this CLI's options line, clamped. No GPU: the
# one job's "video" is not one, so the CLI fails before any model loads.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
WORK="$(mktemp -d -t lingbot-map-app.XXXXXX)"
PID=""
trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$WORK"' EXIT
if ! $NURL src/main.nu "$WORK/lingbot-map" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the CLI does not build:"; tail -6 "$WORK/build.err"; exit 1
fi
PORT=$(( 20000 + $$ % 20000 ))
B="http://127.0.0.1:$PORT"
LINGBOT_MAP_PASSWORD=sekret "$WORK/lingbot-map" serve --port "$PORT" --data "$WORK/data" >"$WORK/serve.log" 2>&1 &
PID=$!
up=0
for _ in $(seq 1 50); do curl -s -m 1 -o /dev/null "$B/healthz" && { up=1; break; }; sleep 0.1; done
[ $up = 1 ] || { echo "FAIL the server did not come up:"; cat "$WORK/serve.log"; exit 1; }
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: wanted '$2', got '$3'"; fails=$((fails + 1)); fi; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
A="-u any:sekret"
check "the sign-in names the model" 1 "$(curl -s -D - -o /dev/null "$B/" | grep -c 'realm="lingbot-map"')"
PAGE=$(curl -s $A "$B/")
check "the page is titled for the model" 1 "$(echo "$PAGE" | grep -c '<title>lingbot-map</title>')"
check "...shows its own options" 1 "$(echo "$PAGE" | grep -c 'id="o-size"')"
check "...and no template mark is left" 0 "$(echo "$PAGE" | grep -c '%%')"
ID=$(curl -s $A -X POST "$B/api/jobs" -d '{"name":"opts"}' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
printf 'x' > "$WORK/f"
check "an upload" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/clip.mp4")"
waitend() { for _ in $(seq 1 100); do st=$(cat "$WORK/data/jobs/$ID/state"); [ "$st" = failed ] || [ "$st" = done ] && break; sleep 0.1; done; }
check "start" 200 "$(code $A -X POST "$B/api/jobs/$ID/start" -d '{"max_views":5,"voxel":true}')"
check "the options line" "--max-views 5 --image-size auto --conf 1.5 --pixel-stride 1 --voxel auto" "$(cat "$WORK/data/jobs/$ID/opts")"
waitend
check "a video that is not one fails the job" failed "$st"
check "the limits hold: confidence at most 10, stride at most 4, size at most 518" 200 "$(code $A -X POST "$B/api/jobs/$ID/start" -d '{"conf_tenths":500,"pixel_stride":16,"image_size":1000}')"
check "...in the options line" "--max-views 120 --image-size 518 --conf 10.0 --pixel-stride 4" "$(cat "$WORK/data/jobs/$ID/opts")"
waitend
check "...and confidence at least 1, a size in whole patches" 200 "$(code $A -X POST "$B/api/jobs/$ID/start" -d '{"conf_tenths":0,"image_size":400}')"
check "...in the options line" "--max-views 120 --image-size 392 --conf 1.0 --pixel-stride 1" "$(cat "$WORK/data/jobs/$ID/opts")"
waitend
[ "$fails" = 0 ] || exit 1
