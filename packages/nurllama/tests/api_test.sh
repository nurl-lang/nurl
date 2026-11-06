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
#    9. the OpenAI-compatible API: /v1/models, /v1/chat/completions and
#       /v1/completions — object shapes, SSE framing ending in [DONE],
#       usage, finish_reason, a stop sequence spanning two tokens (cut, and
#       never streamed), stream text == non-stream text, refusals in
#       OpenAI's error shape, and the official `openai` client
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

echo "[1/4] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"
export NURLLAMA_HOME="$WORK/store"

echo "[2/4] chat templates + style detection (offline)"
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

# A reasoning reply's parser (src/api.nu: _api_take, _api_ready,
# _api_parts), fed token texts by `nurllama think-split OPEN STOP PIECE…`:
# what a stream sends — ["R", reasoning] / ["C", answer] pieces — and what
# one whole reply gives, ["END", has, reasoning, answer, stopped].
ts_case() {   # <label> <expected> <open> <stop> <piece…>
    local label="$1" want="$2"; shift 2
    local got; got=$("$NL" think-split "$@")
    [ "$got" = "$want" ] && ok "think split: $label" || { bad "think split: $label"; printf '    got:\n%s\n    want:\n%s\n' "$got" "$want"; }
}
NLc=$'\n'
ts_case "a </think> split across two tokens is held, then cut" '["R","Let me"]
["R"," think"]
["C","The ans"]
["C","wer."]
["END",true,"Let me think","The answer.",false]' 1 "" "Let me" " think</th" "ink>The ans" "wer."
ts_case "a reply that opens <think> itself, after whitespace" '["R","r1"]
["C","\n\nA"]
["END",true,"r1","\n\nA",false]' 0 "" "$NLc" "<thi" "nk>r1" "</think>${NLc}${NLc}A"
ts_case "a plain reply is all answer" '["C","Hello"]
["C"," world"]
["END",false,"","Hello world",false]' 0 "" "Hello" " world"
ts_case "a reply that starts like <think> but is not" '["C","<b>bold"]
["END",false,"","<b>bold",false]' 0 "" "<" "b>bold"
ts_case "a stop sequence ends the answer, not the reasoning" '["R","a. b"]
["C","c"]
["END",true,"a. b","c",true]' 1 "." "a. b" "</think>c. d"
ts_case "a reasoning block that never closes is all reasoning" '["R","only "]
["R","reasoning "]
["R","</thi"]
["END",true,"only reasoning </thi","",false]' 1 "" "only " "reasoning </thi"

echo "[3/4] ollama HTTP API (net-gated: needs a real model)"
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
curl -s -X POST "http://127.0.0.1:$PORT/api/generate" \
    -d '{"model":"stories260K","prompt":"Once upon a time","stream":false,"options":{"num_predict":40,"temperature":0,"stop":["."]}}' \
    | python3 -c 'import json,sys; o=json.load(sys.stdin); sys.exit(0 if "." not in o["response"] and o["done_reason"]=="stop" else 1)' \
    && ok "ollama options.stop ends the reply before the stop" || bad "ollama options.stop"

echo "[4/4] OpenAI-compatible API (/v1)"
B="http://127.0.0.1:$PORT/v1"
curl -s "$B/models" | python3 -c 'import json,sys; o=json.load(sys.stdin); sys.exit(0 if o["object"]=="list" and any(m["id"]=="stories260K" and m["object"]=="model" for m in o["data"]) else 1)' \
    && ok "GET /v1/models lists the store" || bad "GET /v1/models"
curl -s "$B/models/stories260K" | grep -q '"id":"stories260K"' && ok "GET /v1/models/:id" || bad "GET /v1/models/:id"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$B/models/nope")" = 404 ] && ok "GET /v1/models/:id of an unknown model → 404" || bad "unknown /v1 model"

CHAT='{"model":"stories260K","messages":[{"role":"user","content":"Once upon a time"}],"max_tokens":12,"temperature":0'
curl -s "$B/chat/completions" -d "$CHAT}" > "$WORK/oai_once.json"
python3 - "$WORK/oai_once.json" <<'PYEOF' && ok "chat.completion: shape, finish_reason length, usage" || bad "chat.completion shape"
import json, sys
o = json.load(open(sys.argv[1]))
assert o["object"] == "chat.completion" and o["id"].startswith("chatcmpl-") and o["model"] == "stories260K"
c = o["choices"][0]
assert c["index"] == 0 and c["message"]["role"] == "assistant" and c["message"]["content"]
assert c["finish_reason"] == "length"
u = o["usage"]
assert u["completion_tokens"] == 12 and u["total_tokens"] == u["prompt_tokens"] + 12
PYEOF
curl -sN "$B/chat/completions" -d "$CHAT,\"stream\":true,\"stream_options\":{\"include_usage\":true}}" > "$WORK/oai_stream.sse"
python3 - "$WORK/oai_stream.sse" "$WORK/oai_once.json" <<'PYEOF' && ok "SSE stream: role first, deltas, finish, usage, [DONE]; text == non-stream" || bad "SSE stream"
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
events = [e for e in raw.split("\n\n") if e.strip()]
assert all(e.startswith("data: ") for e in events), "not SSE"
assert events[-1] == "data: [DONE]", "no [DONE]"
objs = [json.loads(e[6:]) for e in events[:-1]]
assert all(o["object"] == "chat.completion.chunk" for o in objs)
assert len({o["id"] for o in objs}) == 1, "one id per stream"
assert objs[0]["choices"][0]["delta"].get("role") == "assistant"
assert objs[-1]["choices"] == [] and objs[-1]["usage"]["completion_tokens"] == 12, "usage chunk"
assert objs[-2]["choices"][0]["finish_reason"] == "length"
text = "".join(o["choices"][0]["delta"].get("content") or "" for o in objs if o["choices"])
once = json.load(open(sys.argv[2]))["choices"][0]["message"]["content"]
assert text == once, (text, once)
PYEOF

# A stop sequence that spans two tokens (" girl" + " named"): never sent,
# not even its first half, streaming or not
STOP=',"stop":["l nam"],"max_tokens":30}'
curl -s "$B/completions" -d "{\"model\":\"stories260K\",\"prompt\":\"Once upon a time\",\"temperature\":0$STOP" > "$WORK/stop_once.json"
curl -sN "$B/completions" -d "{\"model\":\"stories260K\",\"prompt\":\"Once upon a time\",\"temperature\":0,\"stream\":true$STOP" > "$WORK/stop_stream.sse"
python3 - "$WORK/stop_once.json" "$WORK/stop_stream.sse" <<'PYEOF' && ok "a stop spanning two tokens: cut, finish_reason stop, stream == non-stream" || bad "stop across tokens"
import json, sys
o = json.load(open(sys.argv[1]))
assert o["object"] == "text_completion"
t = o["choices"][0]["text"]
assert o["choices"][0]["finish_reason"] == "stop" and t.endswith("gir") and "l nam" not in t, t
ev = [e[6:] for e in open(sys.argv[2], encoding="utf-8").read().split("\n\n") if e.strip()]
assert ev[-1] == "[DONE]"
s = "".join(json.loads(e)["choices"][0]["text"] for e in ev[:-1])
assert s == t, (s, t)
PYEOF

curl -s "$B/chat/completions" -d '{"model":"stories260K","messages":[{"role":"user","content":"x"}],"n":2}' \
    | grep -q '"type":"invalid_request_error"' && ok "n > 1 is refused in OpenAI's error shape" || bad "n > 1"
curl -s "$B/chat/completions" -d '{"model":"stories260K","messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"x"}}]}]}' \
    | grep -q 'only text' && ok "an image part is refused, not dropped" || bad "image part"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$B/chat/completions" -d '{"model":"nope","messages":[]}')" = 404 ] \
    && ok "unknown model → 404 model_not_found" || bad "unknown model (v1)"

if python3 -c 'import openai' >/dev/null 2>&1; then
    python3 - "$PORT" <<'PYEOF' && ok "the official openai client: models, chat, stream, completions" || bad "openai client"
import sys
from openai import OpenAI
c = OpenAI(base_url="http://127.0.0.1:%s/v1" % sys.argv[1], api_key="none")
assert "stories260K" in [m.id for m in c.models.list()]
r = c.chat.completions.create(model="stories260K", messages=[{"role": "user", "content": "Once upon a time"}], max_tokens=12, temperature=0)
s = c.chat.completions.create(model="stories260K", messages=[{"role": "user", "content": "Once upon a time"}], max_tokens=12, temperature=0, stream=True)
assert "".join((ch.choices[0].delta.content or "") for ch in s if ch.choices) == r.choices[0].message.content
t = c.completions.create(model="stories260K", prompt="Once upon a time", max_tokens=12, temperature=0)
assert t.choices[0].text == r.choices[0].message.content
PYEOF
else
    echo "  SKIP the openai client (pip install openai)"
fi

echo "== nurllama api tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
