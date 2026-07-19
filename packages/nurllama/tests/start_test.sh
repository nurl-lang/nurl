#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/start_test.sh — proof of `nurllama start`: the setup wizard,
#  the config file, the web chat server with per-client cookie sessions,
#  the SQLite conversation store, and token auth.
#
#    1. wizard: answers piped on stdin → config.json with the right
#       values; a network+token run generates a token
#    2. `start -y` reuses an existing config without prompting
#    3. server: GET / serves the web UI + a Set-Cookie GUID to a
#       browser, and the ollama status line to a plain client
#    4. sessions: two cookie jars are two clients; each sees only its
#       own conversations (scoping)
#    5. token auth: the page is always served, but /web/* is 401 without
#       the bearer token and 200 with it
#    6. (model-gated) a real chat turn round-trips through /web/chat and
#       persists to the DB
#
#  Run from the package dir:  ./tests/start_test.sh
#  NURLLAMA_LLADA_GGUF=/path/to/llada2.gguf enables the generation check.
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

command -v curl >/dev/null 2>&1 || { echo "  SKIP (needs curl)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "  SKIP (needs python3)"; exit 0; }

WORK="$(mktemp -d -t nurllama-start.XXXXXX)"
PORT=$(( 18700 + (RANDOM % 800) ))
SRVPID=""
cleanup() { [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

for d in gguf safetensor gpu tokenizer http; do
    [ -e "deps/$d" ] || { mkdir -p deps && ln -s "../../$d" "deps/$d"; }
done

echo "[1/4] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

echo "[2/4] the wizard writes a config"
export NURLLAMA_HOME="$WORK/home"
mkdir -p "$WORK/models"
: > "$WORK/models/tiny-a.gguf"
: > "$WORK/models/tiny-b.gguf"
# answers: models_dir, model #2, network(2), token-auth(1), custom token, port
printf '%s\n2\n2\n1\nmytoken\n%s\n' "$WORK/models" "$PORT" \
    | timeout 10 "$NL" start >/dev/null 2>&1 &
WPID=$!
sleep 4
kill "$WPID" 2>/dev/null
python3 - "$NURLLAMA_HOME/config.json" "$WORK/models" "$PORT" <<'EOF'
import json, sys
cfg = json.load(open(sys.argv[1]))
ok = True
def check(name, got, want):
    global ok
    if got != want:
        print(f"  FAIL config {name}: {got!r} != {want!r}"); ok = False
    else:
        print(f"  PASS config {name} = {got!r}")
check("host", cfg["host"], "0.0.0.0")          # chose network
check("auth", cfg["auth"], "token")            # chose token
check("token", cfg["token"], "mytoken")        # custom token
check("port", cfg["port"], int(sys.argv[3]))
check("models_dir", cfg["models_dir"], sys.argv[2])
# a .gguf under the models dir was picked (dir listing order is not sorted)
check("model is a models-dir gguf",
      cfg["model"].startswith(sys.argv[2]) and cfg["model"].endswith(".gguf"), True)
sys.exit(0 if ok else 1)
EOF
[ $? = 0 ] && ok "wizard config values" || bad "wizard config values"

echo "[3/4] start -y reuses the config; server + cookies + auth"
# rewrite the config to localhost + open + a real-or-dummy model on our test port
MODEL="${NURLLAMA_LLADA_GGUF:-$WORK/models/tiny-a.gguf}"
cat > "$NURLLAMA_HOME/config.json" <<EOF
{ "model": "$MODEL", "host": "127.0.0.1", "port": $PORT, "auth": "open", "token": "", "models_dir": "$WORK/models" }
EOF
"$NL" start -y > "$WORK/srv.log" 2>&1 &
SRVPID=$!
sleep 3
base="http://127.0.0.1:$PORT"

# -y must not prompt: the server came up
if grep -q "serving on" "$WORK/srv.log"; then ok "start -y serves without prompting"; else bad "start -y"; fi

# browser gets HTML + a cookie; plain client gets the status line
hdrs=$(curl -s -D - -H 'Accept: text/html' -o "$WORK/page.html" "$base/")
printf '%s' "$hdrs" | grep -qi 'Set-Cookie: nl_client=' && ok "GET / sets an nl_client cookie" || bad "cookie on /"
grep -qi 'text/html' <<<"$hdrs" && grep -q 'nurllama' "$WORK/page.html" && ok "GET / serves the web UI to a browser" || bad "web UI"
[ "$(curl -s "$base/")" = "nurllama is running" ] && ok "GET / keeps the ollama status line" || bad "ollama compat"

# session mints a guid per cookie jar
g1=$(curl -s -c "$WORK/j1" "$base/web/session" | python3 -c 'import json,sys;print(json.load(sys.stdin)["client"])')
g2=$(curl -s -c "$WORK/j2" "$base/web/session" | python3 -c 'import json,sys;print(json.load(sys.stdin)["client"])')
[ -n "$g1" ] && [ -n "$g2" ] && [ "$g1" != "$g2" ] && ok "two clients get distinct GUIDs" || bad "distinct GUIDs"

echo "[4/4] token auth"
kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null
cat > "$NURLLAMA_HOME/config.json" <<EOF
{ "model": "$MODEL", "host": "127.0.0.1", "port": $PORT, "auth": "token", "token": "sekret", "models_dir": "$WORK/models" }
EOF
"$NL" start -y > "$WORK/srv2.log" 2>&1 &
SRVPID=$!
sleep 3
[ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Accept: text/html' "$base/")" = 200 ] && ok "login page served without a token" || bad "login page"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$base/web/session")" = 401 ] && ok "no token → 401" || bad "no token"
[ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer sekret' "$base/web/session")" = 200 ] && ok "correct token → 200" || bad "token 200"

# model-gated: a real chat turn persists and scopes
if [ -n "${NURLLAMA_LLADA_GGUF:-}" ] && [ -f "$NURLLAMA_LLADA_GGUF" ]; then
    kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null
    cat > "$NURLLAMA_HOME/config.json" <<EOF
{ "model": "$NURLLAMA_LLADA_GGUF", "host": "127.0.0.1", "port": $PORT, "auth": "open", "token": "", "models_dir": "$WORK/models" }
EOF
    "$NL" start -y > "$WORK/srv3.log" 2>&1 &
    SRVPID=$!
    sleep 3
    reply=$(curl -s -c "$WORK/jc" -b "$WORK/jc" -X POST "$base/web/chat" \
        -H 'Content-Type: application/json' \
        -d '{"conversation_id":null,"content":"What is the capital of France? One word."}' \
        --max-time 240 | python3 -c 'import json,sys;print(json.load(sys.stdin)["reply"])')
    printf '%s' "$reply" | grep -qi 'paris' && ok "web chat generates a real reply ($reply)" || bad "web chat reply ($reply)"
    n=$(curl -s -b "$WORK/jc" "$base/web/conversations" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')
    [ "$n" = 1 ] && ok "the conversation is listed for its client" || bad "conversation listing"
    other=$(curl -s "$base/web/conversations")
    [ "$other" = "[]" ] && ok "a different client sees no conversations (scoping)" || bad "scoping ($other)"
else
    echo "  SKIP web-chat generation (set NURLLAMA_LLADA_GGUF=/path/to/llada2.gguf)"
fi

echo "== nurllama start tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
