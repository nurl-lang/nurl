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
FIXTURES=""
# only the processes this test started: the server and its fixtures
cleanup() {
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
    for f in $FIXTURES; do kill "$f" 2>/dev/null; done
    chmod -R u+w "$WORK" 2>/dev/null
    [ -n "${KEEP:-}" ] && cp "$WORK/lifecycle.log" "$KEEP" 2>/dev/null
    rm -rf "$WORK"
}
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
# 3-D objects: the status before any, the refusals
check "no object yet" '"state":"none"' "$(curl -s $A "$B/api/jobs/$ID/mesh" | grep -o '"state":"none"')"
check "a mesh request without a six-number box is refused" 400 "$(code $A -X POST "$B/api/jobs/$ID/mesh" -d '{"box":[0,0,0,1,1]}')"
check "a mesh request with a non-number in the box is refused" 400 "$(code $A -X POST "$B/api/jobs/$ID/mesh" -d '{"box":[0,0,0,1,1,"x"]}')"
check "a mesh of a job not done is refused" 409 "$(code $A -X POST "$B/api/jobs/$ID/mesh" -d '{"box":[0,0,0,1,1,1]}')"
echo done > "$WORK/data/jobs/$ID/state"
check "a mesh of a job that kept no views is refused" 409 "$(code $A -X POST "$B/api/jobs/$ID/mesh" -d '{"box":[0,0,0,1,1,1]}')"
check "...for that reason" 1 "$(curl -s $A -X POST "$B/api/jobs/$ID/mesh" -d '{"box":[0,0,0,1,1,1]}' | grep -c 'kept no views')"
echo uploading > "$WORK/data/jobs/$ID/state"
check "no object to download" 404 "$(code $A "$B/jobs/$ID/object.glb")"
check "the job lists its files" 5 "$(curl -s $A "$B/api/jobs/$ID" | sed -n 's/.*"files":\([0-9]*\).*/\1/p')"
# a job that starts: options become the CLI's flags, and a "photo" that
# does not decode fails in the CLI before any model is loaded
ID2=$(curl -s $A -X POST "$B/api/jobs" -d '{"name":"opts"}' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
check "an upload for the run" 201 "$(code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$ID2/files/p.jpg")"
check "start" 200 "$(code $A -X POST "$B/api/jobs/$ID2/start" -d '{"max_views":5,"align":2,"mv_check":1,"voxel_mm":5,"window":99}')"
check "the options line" "--max-views 5 --stride 1 --pixel-stride 1 --window 64 --align 2 --mv-check 1 --voxel 0.005" "$(cat "$WORK/data/jobs/$ID2/opts")"
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

# helpers for the child-lifecycle cases: bounded waits, never bare sleeps
up_or_fail() {
    for _ in $(seq 1 100); do curl -s -m 1 -o /dev/null "$B/healthz" && return 0; sleep 0.1; done
    echo "FAIL the server did not come back"; fails=$((fails + 1)); return 1
}
until_state() {  # job-dir state... — wait up to 30 s for one of them
    d=$1; shift
    for _ in $(seq 1 300); do
        st=$(cat "$d/state" 2>/dev/null)
        for w in "$@"; do [ "$st" = "$w" ] && return 0; done
        sleep 0.1
    done
    return 1
}
newjob() {
    j=$(curl -s $A -X POST "$B/api/jobs" -d '{"name":"lifecycle"}' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
    code $A -X PUT --data-binary @"$WORK/f" "$B/api/jobs/$j/files/p.jpg" >/dev/null
    echo "$j"
}
# Wait at most $2 s for fixture $1 to exit (a zombie counts as exited),
# then reap it and drop it from FIXTURES so cleanup never signals a pid
# the system may have handed to someone else. Past the deadline: fail,
# SIGKILL it, reap it. Returns its exit status.
reap() {
    n=$(( $2 * 10 ))
    while [ "$n" -gt 0 ]; do
        st=$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)
        { [ -z "$st" ] || [ "$st" = Z ]; } && break
        sleep 0.1; n=$((n - 1))
    done
    if [ "$n" -le 0 ]; then
        echo "FAIL fixture $1 did not exit within $2 s"; fails=$((fails + 1))
        kill -KILL "$1" 2>/dev/null
    fi
    wait "$1"; rrc=$?
    FIXTURES=$(echo " $FIXTURES " | sed "s/ $1 / /")
    return $rrc
}

# 1. A child delayed past recovery. With the server down, a job is left
# `running` with no pid yet and a shell held back until the test lets it
# go. The server comes up, waits 2 s for a pid, voids the run's token and
# queues the job again; only after the void is seen is the shell released,
# and it must stop at its token — the sentinel it would write past the
# check never appears.
ID3=$(newjob)
J3="$WORK/data/jobs/$ID3"
kill "$PID"; wait "$PID" 2>/dev/null
echo running > "$J3/state"; echo tok123 > "$J3/run"; rm -f "$J3"/pid.*
( cd "$J3" && exec sh -c 'while [ ! -e go ]; do sleep 0.1; done; echo $$ > pid.tok123 && [ "$(cat run)" = tok123 ] && touch ran' ) &
LATE=$!
FIXTURES="$FIXTURES $LATE"
"$WORK/map-anything" serve --port "$PORT" --data "$WORK/data" >>"$WORK/lifecycle.log" 2>&1 &
PID=$!
up_or_fail
for _ in $(seq 1 100); do [ "$(cat "$J3/run")" != tok123 ] && break; sleep 0.1; done
check "recovery voided the run's token" 1 "$([ "$(cat "$J3/run")" != tok123 ] && echo 1 || echo 0)"
touch "$J3/go"
reap "$LATE" 10
check "a shell delayed past recovery stops at its token" 0 "$(ls "$J3" | grep -c '^ran$')"
until_state "$J3" failed done
check "...and the job runs again, once, to its end" failed "$(cat "$J3/state")"

# 2. A stale shell cannot hide the current run, and nothing replaces a
# run while it is still alive. Run B is active (pid in pid.tokB, its
# command line naming cloud.tmp.ply like a reconstruction's) with the
# server up; a shell of an older run A resumes, publishes into pid.tokA
# and stops at its token; then the server dies by SIGKILL. The next server
# signals B, which lingers 3 s in its SIGTERM trap: for as long as B is
# alive the job must stay `running` with no new run started.
ID4=$(newjob)
J4="$WORK/data/jobs/$ID4"
echo running > "$J4/state"; echo tokB > "$J4/run"; rm -f "$J4"/pid.*
( cd "$J4" && exec sh -c 'trap "touch b.term; sleep 3; exit 143" TERM; echo $$ > pid.tokB; while :; do sleep 0.2; done' run-b cloud.tmp.ply ) &
BPID=$!
FIXTURES="$FIXTURES $BPID"
for _ in $(seq 1 50); do [ -s "$J4/pid.tokB" ] && break; sleep 0.1; done
( cd "$J4" && exec sh -c 'echo $$ > pid.tokA && [ "$(cat run)" = tokA ] && touch ranA' ) &
APID=$!
FIXTURES="$FIXTURES $APID"
reap "$APID" 10
check "the stale shell left the current run's pid alone" "$BPID" "$(cat "$J4/pid.tokB")"
# recovery runs before the listener opens, so watch B's trap now and look
# for the server's readiness only afterwards
kill -KILL "$PID"; wait "$PID" 2>/dev/null
"$WORK/map-anything" serve --port "$PORT" --data "$WORK/data" >>"$WORK/lifecycle.log" 2>&1 &
PID=$!
for _ in $(seq 1 150); do [ -e "$J4/b.term" ] && break; sleep 0.1; done
check "recovery signalled the active run" 1 "$([ -e "$J4/b.term" ] && echo 1 || echo 0)"
s0=$(cat "$J4/started" 2>/dev/null)
sleep 2  # B is still in its trap: a replacement now would overlap it
check "no replacement while the active run is alive" "running $s0" "$(cat "$J4/state") $(cat "$J4/started" 2>/dev/null)"
reap "$BPID" 15; brc=$?
up_or_fail
check "...which then ended (SIGTERM, not its natural end)" 143 "$brc"
check "...the stale shell never ran" 0 "$(ls "$J4" | grep -c '^ranA$')"
until_state "$J4" failed done
check "...and the job ran again, once" failed "$(cat "$J4/state")"

# 2b. A recorded pid whose process is gone (the run died with the server):
# recovery finds the pid dead, queues the job again, and it runs to its end.
ID7=$(newjob)
J7="$WORK/data/jobs/$ID7"
( exit 0 ) &
DEAD=$!
wait "$DEAD"
kill -KILL "$PID"; wait "$PID" 2>/dev/null
echo running > "$J7/state"; echo tokD > "$J7/run"; rm -f "$J7"/pid.*; echo "$DEAD" > "$J7/pid.tokD"
"$WORK/map-anything" serve --port "$PORT" --data "$WORK/data" >>"$WORK/lifecycle.log" 2>&1 &
PID=$!
up_or_fail
until_state "$J7" failed done
check "a dead recorded pid: the job is queued again and runs to its end" failed "$(cat "$J7/state")"
check "...and its pid files are cleared" 0 "$(ls "$J7" | grep -c '^pid\.tokD$')"

# 3. An unsettled job holds the queue. A job is left `running` whose token
# recovery cannot void (its directory is read-only); a second job waits in
# the queue. The first stays `running` and the second must not start.
ID5=$(newjob)
J5="$WORK/data/jobs/$ID5"
ID6=$(newjob)
J6="$WORK/data/jobs/$ID6"
kill "$PID"; wait "$PID" 2>/dev/null
echo running > "$J5/state"; echo tokX > "$J5/run"; rm -f "$J5"/pid.*
echo "--max-views 1" > "$J6/opts"; echo queued > "$J6/state"
chmod 555 "$J5"
"$WORK/map-anything" serve --port "$PORT" --data "$WORK/data" >>"$WORK/lifecycle.log" 2>&1 &
PID=$!
up_or_fail
for _ in $(seq 1 100); do grep -q "cannot void the run token of job $ID5" "$WORK/lifecycle.log" && break; sleep 0.1; done
check "recovery that cannot void a token leaves the job running" running "$(cat "$J5/state")"
sleep 3  # several worker polls
check "...and no queued job starts beside it" queued "$(cat "$J6/state")"
chmod 755 "$J5"

[ $fails = 0 ] || exit 1
