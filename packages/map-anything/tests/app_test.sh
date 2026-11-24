#!/bin/sh
# What `map-anything serve` adds to recon-kit's service (whose own test,
# packages/recon-kit/tests/serve_test.sh, covers the routes, uploads, the
# job lifecycle and 3-D objects): the page shows this model's options, and
# a start request becomes this CLI's options line. No GPU and no download:
# the checkpoint is a local stand-in (hub_get takes an existing path as it
# is), and the one job's "photo" does not decode, so the run fails before
# any model is loaded.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
WORK="$(mktemp -d -t map-anything-app.XXXXXX)"
PID=""
trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$WORK"' EXIT
if ! $NURL src/main.nu "$WORK/map-anything" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the CLI does not build:"; tail -6 "$WORK/build.err"; exit 1
fi
PORT=$(( 20000 + $$ % 20000 ))
B="http://127.0.0.1:$PORT"
printf 'not a checkpoint' > "$WORK/model.safetensors"
MAP_ANYTHING_MODEL="$WORK/model.safetensors" MAP_ANYTHING_PASSWORD=sekret "$WORK/map-anything" serve --port "$PORT" --data "$WORK/data" >"$WORK/serve.log" 2>&1 &
PID=$!
up=0
for _ in $(seq 1 50); do curl -s -m 1 -o /dev/null "$B/healthz" && { up=1; break; }; sleep 0.1; done
[ $up = 1 ] || { echo "FAIL the server did not come up:"; cat "$WORK/serve.log"; exit 1; }
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: wanted '$2', got '$3'"; fails=$((fails + 1)); fi; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
A="-u any:sekret"
check "the sign-in names the model" 1 "$(curl -s -D - -o /dev/null "$B/" | grep -c 'realm="map-anything"')"
PAGE=$(curl -s $A "$B/")
check "the page is titled for the model" 1 "$(echo "$PAGE" | grep -c '<title>map-anything</title>')"
check "...shows its own options" 1 "$(echo "$PAGE" | grep -c 'id="o-align"')"
check "...and no template mark is left" 0 "$(echo "$PAGE" | grep -c '%%')"
ID=$(curl -s $A -X POST "$B/api/jobs" -d '{"name":"opts"}' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
printf 'x' > "$WORK/f"
check "an upload" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/p.jpg")"
check "start" 200 "$(code $A -X POST "$B/api/jobs/$ID/start" -d '{"max_views":5,"align":2,"mv_check":1,"voxel_mm":5,"window":99}')"
check "the options line" "--max-views 5 --stride 1 --pixel-stride 1 --window 64 --align 2 --mv-check 1 --voxel 0.005" "$(cat "$WORK/data/jobs/$ID/opts")"
for _ in $(seq 1 100); do st=$(cat "$WORK/data/jobs/$ID/state"); [ "$st" = failed ] || [ "$st" = done ] && break; sleep 0.1; done
check "...the limits hold: confidence at most 50 %, pixel stride at most 4" 1 "$(curl -s -o /dev/null $A -X POST "$B/api/jobs/$ID/start" -d '{"conf_pct":95,"pixel_stride":16}'; grep -c -- '--pixel-stride 4 .*--conf-pct 50' "$WORK/data/jobs/$ID/opts")"
for _ in $(seq 1 100); do
    st=$(cat "$WORK/data/jobs/$ID/state")
    [ "$st" = failed ] || [ "$st" = done ] && break
    sleep 0.1
done
check "an undecodable photo fails the job" failed "$st"
check "...and the run's output is its log" 1 "$(grep -c . "$WORK/data/jobs/$ID/log" | awk '{print ($1 > 0)}')"
[ "$fails" = 0 ] || exit 1
