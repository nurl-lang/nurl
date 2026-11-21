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
check "a second file that cleans to the same name is refused" 409 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/a.jpg")"
printf 'abc' > "$WORK/g"
check "a file in pieces: the first" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/big.png?offset=0")"
check "...a piece that does not continue it is refused" 409 "$(code $A -X PUT --data-binary @"$WORK/g" "$B/api/jobs/$ID/files/big.png?offset=5")"
check "...the next piece" 201 "$(code $A -X PUT --data-binary @"$WORK/g" "$B/api/jobs/$ID/files/big.png?offset=1")"
check "...and the file is whole" "xabc" "$(cat "$WORK/data/jobs/$ID/input/big.png")"
LONG=$(printf 'a%.0s' $(seq 1 130))
check "a long name keeps its extension" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/$LONG.jpg")"
check "...cut to 120 bytes" 1 "$(ls "$WORK/data/jobs/$ID/input" | grep -c '^a\{116\}\.jpg$')"
check "a video beside photos is refused" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID/files/clip.mp4")"
check "...at start" 400 "$(code $A -X POST "$B/api/jobs/$ID/start" -d '{}')"
check "a bad job id" 400 "$(code $A "$B/api/jobs/..%2Fx")"
check "an unknown job" 404 "$(code $A "$B/api/jobs/123-abc")"
check "no cloud yet" 404 "$(code $A "$B/jobs/$ID/cloud.ply")"
check "the job lists its files" 5 "$(curl -s $A "$B/api/jobs/$ID" | sed -n 's/.*"files":\([0-9]*\).*/\1/p')"
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

# two first pieces for one name at the same moment: exactly one is stored
racers=""
for n in 1 2 3 4 5 6; do
    curl -s -o /dev/null -w '%{http_code}\n' $A -X PUT --data-binary @"$WORK/g" "$B/api/jobs/$ID/files/race.jpg?offset=0" >> "$WORK/race" &
    racers="$racers $!"
done
# only the uploads: a bare `wait` would wait for the server too
for r in $racers; do wait "$r"; done
check "concurrent uploads of one name: one stored" 1 "$(grep -c 201 "$WORK/race")"
check "...the rest refused" 5 "$(grep -c 409 "$WORK/race")"

# the data directory has one owner
"$WORK/map-anything" serve --port $((PORT + 1)) --data "$WORK/data" >"$WORK/second.log" 2>&1
check "a second server on the same data is refused" 1 "$(grep -c 'another server already owns' "$WORK/second.log")"

check "delete" 204 "$(code $A -X DELETE "$B/api/jobs/$ID")"
check "...and it is gone" 0 "$(ls "$WORK/data/jobs" | wc -l | tr -d ' ')"

# the lock goes with its process, however it ends: a server killed with
# SIGKILL leaves nothing that keeps the next one out
kill -KILL "$PID"; wait "$PID" 2>/dev/null; PID=""
"$WORK/map-anything" serve --port "$PORT" --data "$WORK/data" >"$WORK/third.log" 2>&1 &
PID=$!
up=0
for _ in $(seq 1 50); do curl -s -m 1 -o /dev/null "$B/healthz" && { up=1; break; }; sleep 0.1; done
check "a killed server's lock does not keep the next one out" 1 "$up"

# a child delayed past recovery: the server comes up to find a job
# `running` with no pid yet; it waits, voids the run's token and queues
# the job again. When the late shell finally writes its pid it sees the
# void and exits instead of starting a second reconstruction.
ID3=$(curl -s $A -X POST "$B/api/jobs" -d '{"name":"late"}' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID3/files/p.jpg" >/dev/null
kill "$PID"; wait "$PID" 2>/dev/null; PID=""
J3="$WORK/data/jobs/$ID3"
echo running > "$J3/state"; echo tok123 > "$J3/run"; rm -f "$J3/pid"
MARK="late-child-$$"
(cd "$J3" && sh -c "sleep 4; echo \$\$ > pid && [ \"\$(cat run)\" = tok123 ] && exec sleep 30 $MARK" 2>/dev/null &)
"$WORK/map-anything" serve --port "$PORT" --data "$WORK/data" >"$WORK/fourth.log" 2>&1 &
PID=$!
sleep 7
check "a child delayed past recovery never starts" 0 "$(pgrep -fc "sleep 30 $MARK")"
check "...and the job ran again, once, to its end" failed "$(cat "$J3/state")"

[ $fails = 0 ] || exit 1
