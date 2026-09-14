#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/agora_test.sh — the package's full test suite:
#    1. unit suite  : store, every operation, the router, MCP dispatch
#                     (tests/agora_test.nu, one process, no socket)
#    2. CLI         : agora <op> key=value --as NAME on a scratch file;
#                     two identities talking through the file alone
#    3. live HTTP   : REST (/api) and MCP (/mcp) over curl against a
#                     running server with a worker pool, bearer auth
#    4. concurrency : 24 parallel claims of one task → exactly one wins;
#                     parallel inbox drains → every message delivered
#                     exactly once
#    5. stdio       : MCP over stdin/stdout as a local identity
#
#  Run from the package dir:  ./tests/agora_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
#       PORT (default 8820)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

PORT="${PORT:-8820}"
WORK="$(mktemp -d -t agora-test.XXXXXX)"
SERVE_PID=""
cleanup() { [ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null; rm -rf "$WORK" agora_test_scratch; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }
has()   { case "$2" in *"$3"*) ok "$1";; *) bad "$1 (missing '$3')";; esac; }

echo "[1/5] unit suite"
rm -rf agora_test_scratch
if ! $NURL tests/agora_test.nu "$WORK/unit" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tests/agora_test.nu:"; tail -5 "$WORK/build.err"; exit 1
fi
if "$WORK/unit" > "$WORK/unit.out" 2>&1; then
    ok "agora_test.nu ($(tail -1 "$WORK/unit.out"))"
else
    bad "agora_test.nu"; grep FAIL "$WORK/unit.out" | head -10
fi
rm -rf agora_test_scratch

echo "[2/5] CLI"
if ! $NURL src/main.nu "$WORK/agora" >/dev/null 2>"$WORK/build2.err"; then
    echo "FAIL: could not build src/main.nu:"; tail -5 "$WORK/build2.err"; exit 1
fi
BIN="$WORK/agora"
export AGORA_DB="$WORK/cli.db"

has "ops lists the catalog" "$("$BIN" ops 2>/dev/null)" "task_claim"
check "--version is the manifest's" "$("$BIN" --version 2>/dev/null | grep -o '[0-9]*\.[0-9]*\.[0-9]*')" "$(grep '^version' nurl.toml | grep -o '[0-9]*\.[0-9]*\.[0-9]*')"
has "a fresh brief" "$("$BIN" brief --as alice 2>/dev/null)" "inbox: nothing new"
check "post" "$("$BIN" post body="hello all" --as bob 2>/dev/null)" "#1 posted to public"
check "send" "$("$BIN" send to=alice body="psst" --as bob 2>/dev/null)" "#2 sent to alice"
has "task_post" "$("$BIN" task_post title="review PR" tags="review" priority=2 --as bob 2>/dev/null)" "task #1 posted"
OUT=$("$BIN" brief --as alice 2>/dev/null)
has "brief delivers the post" "$OUT" "#1 public bob now: hello all"
has "brief delivers the dm" "$OUT" "#2 dm bob now: psst"
has "brief counts open tasks" "$OUT" "open tasks: 1"
has "brief delivers once" "$("$BIN" brief --as alice 2>/dev/null)" "inbox: nothing new"
has "task_claim" "$("$BIN" task_claim id=1 --as alice 2>/dev/null)" "claimed by you"
has "task_done" "$("$BIN" task_done id=1 result="LGTM" --as alice 2>/dev/null)" "done"
OUT=$("$BIN" brief --as bob 2>/dev/null)
has "the poster hears of the claim" "$OUT" "task #1 claimed by alice"
has "and gets the result" "$OUT" "result: LGTM"
has "--json prints the body" "$("$BIN" tasks which=done --json --as alice 2>/dev/null)" '"result":"LGTM"'
"$BIN" post body="x" channel=nope --as alice >/dev/null 2>&1; check "an unknown channel exits 1" "$?" "1"
"$BIN" brief >/dev/null 2>"$WORK/e1.txt"; check "no identity exits 2" "$?" "2"
has "and says how to give one" "$(cat "$WORK/e1.txt")" "--as NAME"
"$BIN" bogus --as alice >/dev/null 2>&1; check "an unknown op exits 2" "$?" "2"

echo "[3/5] live HTTP: REST + MCP"
export AGORA_DB="$WORK/http.db"
"$BIN" serve --addr "127.0.0.1:$PORT" --workers 4 --quiet >"$WORK/serve.log" 2>&1 &
SERVE_PID=$!
for _ in $(seq 60); do
    curl -s -m 1 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && break
    sleep 0.1 2>/dev/null || true
done
U="http://127.0.0.1:$PORT"
J='-H Content-Type:application/json'

check "GET /healthz" "$(curl -s -m 5 "$U/healthz")" "ok"
has "GET /api lists the ops" "$(curl -s -m 5 "$U/api")" '"path":"/api/task_claim"'
check "POST /api/brief without a token is 401" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST "$U/api/brief")" "401"
JOIN=$(curl -s -m 5 $J -X POST -d '{"name":"carol","about":"tester"}' "$U/api/join")
has "POST /api/join" "$JOIN" '"agent":"carol"'
TOK=$(printf '%s' "$JOIN" | sed -n 's/.*"token":"\([0-9a-f]*\)".*/\1/p')
check "the token is 48 hex chars" "${#TOK}" "48"
check "join twice is 409" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' $J -X POST -d '{"name":"carol"}' "$U/api/join")" "409"
A="Authorization: Bearer $TOK"
has "GET /api/whoami with the token" "$(curl -s -m 5 -H "$A" "$U/api/whoami")" '"agent":"carol"'
check "a bad token is 401" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer 0000' "$U/api/whoami")" "401"
"$BIN" post body="from the cli" --as dave >/dev/null 2>&1
has "the CLI and the server share the file" "$(curl -s -m 5 -H "$A" $J -X POST -d '{}' "$U/api/brief")" '"body":"from the cli"'
has "GET with query arguments" "$(curl -s -m 5 -H "$A" "$U/api/history?channel=public&limit=1")" '"from":"dave"'
check "an unknown op is 404" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H "$A" $J -X POST -d '{}' "$U/api/nope")" "404"

MCP='{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
has "MCP tools/list" "$(curl -s -m 5 $J -X POST -d "$MCP" "$U/mcp")" '"name":"brief"'
MCP='{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}'
has "MCP initialize carries the instructions" "$(curl -s -m 5 $J -X POST -d "$MCP" "$U/mcp")" '"instructions":"Agora is where agents meet'
MCP='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whoami","arguments":{}}}'
has "MCP tools/call without a token is a tool error" "$(curl -s -m 5 $J -X POST -d "$MCP" "$U/mcp")" '"isError":true'
has "MCP tools/call with the token acts as the agent" "$(curl -s -m 5 -H "$A" $J -X POST -d "$MCP" "$U/mcp")" 'you: carol'
MCP='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"task_post","arguments":{"title":"race me","tags":"race"}}}'
has "MCP task_post" "$(curl -s -m 5 -H "$A" $J -X POST -d "$MCP" "$U/mcp")" 'task #1 posted'

echo "[4/5] concurrency"
# 24 agents race for task #1 through the worker pool: exactly one wins.
for i in $(seq 24); do
    T=$(curl -s -m 5 $J -X POST -d "{\"name\":\"racer$i\"}" "$U/api/join" | sed -n 's/.*"token":"\([0-9a-f]*\)".*/\1/p')
    echo "$T" >> "$WORK/racers.txt"
done
: > "$WORK/claims.txt"
PIDS=""
while read -r T; do
    curl -s -m 10 -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" $J -X POST -d '{"id":1}' "$U/api/task_claim" >> "$WORK/claims.txt" &
    PIDS="$PIDS $!"
done < "$WORK/racers.txt"
wait $PIDS   # not a bare `wait`: that would also wait for the server
check "24 parallel claims: one 200" "$(grep -c '^200$' "$WORK/claims.txt")" "1"
check "24 parallel claims: 23 409" "$(grep -c '^409$' "$WORK/claims.txt")" "23"

# 40 posts to public, then racer1 drains its inbox from 8 parallel
# readers with limit 7: every message arrives exactly once.
PIDS=""
for i in $(seq 40); do
    curl -s -m 5 -o /dev/null -H "$A" $J -X POST -d "{\"body\":\"m$i\"}" "$U/api/post" &
    PIDS="$PIDS $!"
done
wait $PIDS
R1=$(head -1 "$WORK/racers.txt")
: > "$WORK/drain.txt"
PIDS=""
for _ in $(seq 8); do
    curl -s -m 10 -H "Authorization: Bearer $R1" $J -X POST -d '{"limit":7}' "$U/api/inbox" >> "$WORK/drain.txt" &
    PIDS="$PIDS $!"
done
wait $PIDS
# racer1 joined before the 40 posts and before "race me" was posted by
# carol → sees the 40 m* bodies (its own claim outcome went to carol).
check "parallel drains: 40 distinct bodies" "$(grep -o '"body":"m[0-9]*"' "$WORK/drain.txt" | sort -u | wc -l | tr -d ' ')" "40"
check "parallel drains: no duplicates" "$(grep -o '"body":"m[0-9]*"' "$WORK/drain.txt" | wc -l | tr -d ' ')" "40"
check "and then nothing is left" "$(curl -s -m 5 -H "Authorization: Bearer $R1" $J -X POST -d '{}' "$U/api/inbox" | grep -c '"messages":\[\]')" "1"

kill "$SERVE_PID"; wait "$SERVE_PID" 2>/dev/null; SERVE_PID=""
check "the server log is quiet" "$(wc -c < "$WORK/serve.log" | tr -d ' ')" "0"

echo "[5/5] stdio"
export AGORA_DB="$WORK/stdio.db"
OUT=$(printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"post","arguments":{"body":"via stdio"}}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whoami","arguments":{}}}' \
    | "$BIN" stdio --as erin 2>/dev/null)
has "MCP over stdio posts as --as" "$OUT" '#1 posted to public'
has "and knows who it is" "$OUT" 'you: erin'
has "a second local identity reads it" "$("$BIN" history channel=public --as fred 2>/dev/null)" "#1 public erin now: via stdio"
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | "$BIN" stdio >/dev/null 2>&1; check "stdio without --as exits 2" "$?" "2"

echo
echo "agora: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
