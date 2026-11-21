#!/bin/sh
# `map-anything serve` over HTTP, without a GPU or the checkpoint: every
# route a browser uses, the sign-in, the file-name and job-id checks, and
# the refusals — but no job is ever started, so nothing reaches the model.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t map-anything-serve.XXXXXX)"
PID=""
cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

if ! $NURL src/main.nu "$WORK/map-anything" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the CLI does not build:"; tail -6 "$WORK/build.err"
    exit 1
fi

PORT=$(( 20000 + $$ % 20000 ))
B="http://127.0.0.1:$PORT"
MAP_ANYTHING_PASSWORD=sekret "$WORK/map-anything" serve --port "$PORT" --data "$WORK/data" >"$WORK/serve.log" 2>&1 &
PID=$!
up=0
for _ in $(seq 1 50); do
    curl -s -m 1 -o /dev/null "$B/healthz" && { up=1; break; }
    sleep 0.1
done
[ $up = 1 ] || { echo "FAIL the server did not come up:"; cat "$WORK/serve.log"; exit 1; }

fails=0
check() {  # name expected actual
    if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: wanted '$2', got '$3'"; fails=$((fails + 1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
A="-u any:sekret"

check "health needs no sign-in" 200 "$(code "$B/healthz")"
check "the page needs a sign-in" 401 "$(code "$B/")"
check "a wrong password is refused" 401 "$(code -u any:wrong "$B/api/jobs")"
check "the page" 200 "$(code $A "$B/")"
check "the viewer" 200 "$(code $A "$B/view")"
check "an empty job list" '{"jobs":[]}' "$(curl -s $A "$B/api/jobs")"

ID=$(curl -s $A -X POST "$B/api/jobs" -d '{"name":"test"}' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
[ -n "$ID" ] || { echo "FAIL no job id"; exit 1; }
check "a new job is uploading" uploading "$(cat "$WORK/data/jobs/$ID/state")"
check "starting with no input is refused" 400 "$(code $A -X POST "$B/api/jobs/$ID/start" -d '{}')"

printf 'x' > "$WORK/f"
check "an upload" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/a.jpg")"
check "a traversing name stays inside the job" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/..%2F..%2Fescape.jpg")"
[ -e "$WORK/data/escape.jpg" ] || [ -e "$WORK/data/jobs/escape.jpg" ] && { echo "FAIL a file escaped the job directory"; fails=$((fails + 1)); }
check "a hidden name is made visible" 1 "$(ls -A "$WORK/data/jobs/$ID/input" | grep -c '^_')"
check "a video beside photos is refused" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/clip.mp4")"
check "...at start" 400 "$(code $A -X POST "$B/api/jobs/$ID/start" -d '{}')"
check "a bad job id" 400 "$(code $A "$B/api/jobs/..%2Fx")"
check "an unknown job" 404 "$(code $A "$B/api/jobs/123-abc")"
check "no cloud yet" 404 "$(code $A "$B/jobs/$ID/cloud.ply")"
check "the job lists its files" 3 "$(curl -s $A "$B/api/jobs/$ID" | sed -n 's/.*"files":\([0-9]*\).*/\1/p')"
# a job that starts: options become the CLI's flags, and a "photo" that
# does not decode fails in the CLI before any model is loaded
ID2=$(curl -s $A -X POST "$B/api/jobs" -d '{"name":"opts"}' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
check "an upload for the run" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID2/files/p.jpg")"
check "start" 200 "$(code $A -X POST "$B/api/jobs/$ID2/start" -d '{"max_views":5,"align":2,"mv_check":1,"voxel_mm":5,"window":99}')"
check "the options line" "--max-views 5 --fps 2 --stride 1 --pixel-stride 1 --window 64 --align 2 --mv-check 1 --voxel 0.005" "$(cat "$WORK/data/jobs/$ID2/opts")"
for _ in $(seq 1 100); do
    st=$(cat "$WORK/data/jobs/$ID2/state")
    [ "$st" = failed ] || [ "$st" = done ] && break
    sleep 0.1
done
check "an undecodable photo fails the job" failed "$st"
check "...and starting it again is allowed" 200 "$(code $A -X POST "$B/api/jobs/$ID2/start" -d '{"voxel_mm":-1}')"
check "...with auto voxels" 1 "$(grep -c -- '--voxel auto' "$WORK/data/jobs/$ID2/opts")"
for _ in $(seq 1 100); do
    st=$(cat "$WORK/data/jobs/$ID2/state")
    [ "$st" = failed ] || [ "$st" = done ] && break
    sleep 0.1
done
check "delete the run" 204 "$(code $A -X DELETE "$B/api/jobs/$ID2")"

check "delete" 204 "$(code $A -X DELETE "$B/api/jobs/$ID")"
check "...and it is gone" 0 "$(ls "$WORK/data/jobs" | wc -l | tr -d ' ')"

[ $fails = 0 ] || exit 1
