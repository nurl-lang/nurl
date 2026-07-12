#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/api_test.sh — the ollama-compatible HTTP API + chat templates.
#
#    1. GET  /            → "nurllama is running"
#    2. GET  /api/tags    → the local store as ollama's model list
#    3. POST /api/show    → the model's metadata
#    4. POST /api/generate, stream=true  → NDJSON, ONE OBJECT PER TOKEN,
#       arriving as they decode, terminated by done:true with counts
#    5. POST /api/generate, stream=false → one aggregated object whose
#       text EQUALS the concatenation of the streamed pieces (the two
#       paths cannot drift)
#    6. POST /api/chat    → assistant message shape
#    7. errors: unknown model → 404-shaped JSON error; bad JSON → error
#    8. chat templates: each dialect renders exactly (unit-checked via
#       `nurllama chat-template`, a hidden debug command)
#
#  Run from the package dir:  ./tests/api_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

command -v curl >/dev/null 2>&1 || { echo "SKIP: curl required"; exit 0; }

WORK="$(mktemp -d -t nurllama-api.XXXXXX)"
SRV_PID=""
trap '[ -n "$SRV_PID" ] && kill $SRV_PID 2>/dev/null; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

[ -e deps/gguf ] || { mkdir -p deps && ln -s ../../gguf deps/gguf; }
[ -e deps/gpu ]  || { mkdir -p deps && ln -s ../../gpu deps/gpu; }
[ -e deps/http ] || { mkdir -p deps && ln -s ../../http deps/http; }

echo "[1/3] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"
export NURLLAMA_HOME="$WORK/store"

echo "[2/3] chat templates + style detection (offline)"
"$NL" selftest | grep -q " 0 failed" && ok "selftest (21 checks, incl. style detection from GGUF metadata)" || bad "selftest"
T1=$("$NL" chat-template chatml)
[ "$T1" = '<|im_start|>system
be brief<|im_end|>
<|im_start|>user
hi<|im_end|>
<|im_start|>assistant' ] && ok "ChatML renders exactly" || { bad "ChatML"; printf '%s\n' "$T1"; }
T2=$("$NL" chat-template llama3)
[ "$T2" = '<|start_header_id|>system<|end_header_id|>

be brief<|eot_id|><|start_header_id|>user<|end_header_id|>

hi<|eot_id|><|start_header_id|>assistant<|end_header_id|>' ] && ok "llama3 renders exactly" || { bad "llama3"; printf '%s\n' "$T2"; }
T3=$("$NL" chat-template llama2)
[ "$T3" = '[INST] <<SYS>>
be brief
<</SYS>>

hi [/INST] ' ] && ok "llama2 renders exactly" || { bad "llama2"; printf '%s\n' "$T3"; }
T4=$("$NL" chat-template plain)
[ "$T4" = 'be brief

hi' ] && ok "base model: no invented turns" || { bad "plain"; printf '%s\n' "$T4"; }

echo "[3/3] HTTP API (net-gated: needs a real model)"
if [ "${NURL_NET_TESTS:-0}" != 1 ]; then
    echo "  SKIP (set NURL_NET_TESTS=1 to pull a model and exercise the API)"
    echo "== nurllama api tests: PASS=$PASS FAIL=$FAIL"
    [ "$FAIL" = 0 ]; exit $?
fi

"$NL" pull hf.co/ggml-org/models/tinyllamas/stories260K.gguf >/dev/null || { echo "  SKIP pull failed"; exit 0; }

PORT=$(( (RANDOM % 20000) + 25000 ))
"$NL" serve --port "$PORT" > "$WORK/serve.log" 2>&1 &
SRV_PID=$!
for _ in $(seq 40); do curl -sf "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break; sleep 0.25; done

curl -s "http://127.0.0.1:$PORT/" | grep -q "nurllama is running" && ok "GET /" || bad "GET /"
curl -s "http://127.0.0.1:$PORT/api/tags" | grep -q '"name":"stories260K"' && ok "GET /api/tags lists the store" || bad "GET /api/tags"
curl -s -X POST "http://127.0.0.1:$PORT/api/show" -d '{"model":"stories260K"}' \
    | grep -q '"general.architecture":"llama"' && ok "POST /api/show returns metadata" || bad "POST /api/show"

GEN='{"model":"stories260K","prompt":"Once upon a time","options":{"num_predict":12,"temperature":0}}'
curl -s -X POST "http://127.0.0.1:$PORT/api/generate" -d "$GEN" > "$WORK/stream.ndjson"
LINES=$(wc -l < "$WORK/stream.ndjson")
[ "$LINES" = 13 ] && ok "stream: 12 token frames + 1 done frame" || bad "stream frame count ($LINES)"
head -1 "$WORK/stream.ndjson" | grep -q '"done":false' && ok "stream: token frames carry done:false" || bad "token frame shape"
tail -1 "$WORK/stream.ndjson" | grep -q '"done":true' && ok "stream: final frame carries done:true" || bad "done frame"
tail -1 "$WORK/stream.ndjson" | grep -q '"eval_count":12' && ok "stream: token counts reported" || bad "counts"

# non-stream text must equal the concatenation of the streamed pieces
STREAM_TEXT=$(python3 - "$WORK/stream.ndjson" <<'PYEOF'
import json, sys
out = []
for line in open(sys.argv[1]):
    o = json.loads(line)
    if not o.get('done'): out.append(o['response'])
print(''.join(out))
PYEOF
)
ONESHOT=$(curl -s -X POST "http://127.0.0.1:$PORT/api/generate" \
    -d '{"model":"stories260K","prompt":"Once upon a time","stream":false,"options":{"num_predict":12,"temperature":0}}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["response"])')
[ "$STREAM_TEXT" = "$ONESHOT" ] && ok "stream text == non-stream text (paths cannot drift)" || {
    bad "stream/non-stream drift"; echo "    stream : $STREAM_TEXT"; echo "    oneshot: $ONESHOT"; }

curl -s -X POST "http://127.0.0.1:$PORT/api/chat" \
    -d '{"model":"stories260K","messages":[{"role":"user","content":"Once upon a time"}],"stream":false,"options":{"num_predict":8,"temperature":0}}' \
    | grep -q '"message":{"role":"assistant"' && ok "POST /api/chat returns an assistant message" || bad "POST /api/chat"

curl -s -X POST "http://127.0.0.1:$PORT/api/generate" -d '{"model":"nope","prompt":"x"}' \
    | grep -q '"error"' && ok "unknown model → JSON error" || bad "unknown-model error"
curl -s -X POST "http://127.0.0.1:$PORT/api/generate" -d 'not json' \
    | grep -q '"error"' && ok "malformed body → JSON error" || bad "bad-JSON error"

echo "== nurllama api tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
