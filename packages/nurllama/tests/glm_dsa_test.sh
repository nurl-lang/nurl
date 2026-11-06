#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/glm_dsa_test.sh — proof of the glm-dsa architecture (GLM-5.x:
#  HF `glm_moe_dsa`).
#
#  glm-dsa is MLA attention (a low-rank query, K and V out of one
#  compressed latent, attended in the absorbed form), DeepSeek sparse
#  attention (a lightning indexer picks the index_topk keys each position
#  attends; "shared" layers reuse the last full layer's pick) and a
#  sigmoid-routed MoE with a shared expert. Every part of it can be wrong
#  while the model still produces fluent text, so the reference is HF
#  transformers' own GlmMoeDsaForCausalLM in float32, on a tiny random
#  checkpoint (tests/glm_dsa_ref.py) that llama.cpp's converter turns into
#  the GGUF nurllama reads — the same path a published GLM-5.x GGUF took:
#    1. a prompt of at most index_topk tokens (the indexer selects every
#       key): final-position logits — same argmax, same top-5, delta small
#       against the logit span — and a greedy continuation that runs past
#       index_topk, so the selection starts to bite while decoding
#    2. a prompt longer than index_topk: the selection is active from the
#       prompt on
#    3. a prompt longer than one prefill chunk (64 positions)
#    4. the same checkpoint at q8_0: same argmax, logits near f32's
#    5. the GLM tokenizer (tokenizer.ggml.pre glm4) gives HF's ids
#    6. sampled text served through the OpenAI API is UTF-8, piece by
#       piece and whole
#
#  Needs python3 with torch + transformers >= 5.15 (GlmMoeDsa), the
#  llama.cpp source tree for its converter (LLAMA_CPP=/path/to/llama.cpp),
#  and the GLM-5 tokenizer files (GLM_TOKENIZER_DIR with tokenizer.json and
#  tokenizer_config.json — or NURL_NET_TESTS=1 to fetch them). SKIPs
#  without them.
#
#  Run from the package dir:  ./tests/glm_dsa_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
PY="${PYTHON:-python3}"

WORK="$(mktemp -d -t nurllama-glmdsa.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

for d in gguf safetensor tokenizer gpu http grad nn gpukit tensor hub nurldb; do
    [ -e "deps/$d" ] || { mkdir -p deps && ln -s "../../$d" "deps/$d"; }
done

if ! "$PY" -c 'import numpy, torch; from transformers import GlmMoeDsaForCausalLM' >/dev/null 2>&1; then
    echo "  SKIP (python3 with numpy, torch and transformers >= 5.15 required)"; exit 0
fi
if [ -z "${LLAMA_CPP:-}" ] || [ ! -f "$LLAMA_CPP/convert_hf_to_gguf.py" ]; then
    echo "  SKIP (set LLAMA_CPP to a llama.cpp source tree, for its converter)"; exit 0
fi
TOK="${GLM_TOKENIZER_DIR:-}"
if [ -z "$TOK" ]; then
    if [ "${NURL_NET_TESTS:-0}" != 1 ] || ! command -v curl >/dev/null 2>&1; then
        echo "  SKIP (set GLM_TOKENIZER_DIR, or NURL_NET_TESTS=1 with curl)"; exit 0
    fi
    TOK="$WORK/tok"; mkdir -p "$TOK"
    for f in tokenizer.json tokenizer_config.json; do
        curl -sfL --max-time 600 -o "$TOK/$f" "https://huggingface.co/zai-org/GLM-5.3/resolve/main/$f" \
            || { echo "  SKIP tokenizer download failed"; exit 0; }
    done
fi

echo "[1/7] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

echo "[2/7] the tiny checkpoint, through llama.cpp's converter"
HF="$WORK/hf"
if ! "$PY" tests/glm_dsa_ref.py make "$HF" "$TOK" >"$WORK/make.log" 2>&1; then
    echo "FAIL: could not make the checkpoint:"; tail -5 "$WORK/make.log"; exit 1
fi
for t in f32 q8_0; do
    if ! "$PY" "$LLAMA_CPP/convert_hf_to_gguf.py" "$HF" --outtype "$t" --outfile "$WORK/tiny-$t.gguf" >"$WORK/conv-$t.log" 2>&1; then
        echo "FAIL: llama.cpp could not convert ($t):"; tail -5 "$WORK/conv-$t.log"; exit 1
    fi
done
M="$WORK/tiny-f32.gguf"
ok "made and converted (f32, q8_0)"

# logits + greedy parity for one prompt
parity() {
    local label="$1" prompt="$2" n="$3"
    local ids ref_ids ref_txt our_txt
    ids=$("$NL" tokenize "$M" "$prompt")
    "$NL" logits "$M" "$prompt" > "$WORK/ours.logits"
    "$PY" tests/glm_dsa_ref.py logits "$HF" "$ids" > "$WORK/ref.logits" 2>/dev/null
    "$PY" - "$WORK" <<'PYEOF' && ok "$label: logits match transformers (same argmax + top-5)" || bad "$label: logits parity"
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/ours.logits'); b = np.loadtxt(w+'/ref.logits')
span = b.max() - b.min()
d = np.abs(a-b).max()
print("    max delta %.3g (span %.3g)" % (d, span))
assert a.argmax() == b.argmax(), "argmax differs"
assert list(np.argsort(-a)[:5]) == list(np.argsort(-b)[:5]), "top-5 differ"
assert d < span*1e-4, "max delta %g vs span %g" % (d, span)
PYEOF
    ref_ids=$("$PY" tests/glm_dsa_ref.py greedy "$HF" "$ids" "$n" 2>/dev/null)
    ref_txt=$("$NL" detok "$M" $ref_ids)
    our_txt=$("$NL" run "$M" "$prompt" -n "$n" --temp 0 --ctx 512)
    if [ "$our_txt" = "$ref_txt" ]; then ok "$label: $n-token greedy text == transformers'"; else
        bad "$label: greedy parity"; echo "    ours: $our_txt"; echo "    ref : $ref_txt"; fi
}

# The tiny model's index_topk is 8.
ntok() { "$NL" tokenize "$M" "$1" | wc -w; }

echo "[3/7] a prompt within index_topk, decoding past it"
SHORT="The capital of France is"
N=$(ntok "$SHORT")
[ "$N" -le 8 ] && ok "the short prompt is $N tokens (≤ index_topk 8)" || bad "short prompt is $N tokens"
parity "short prompt" "$SHORT" 16

echo "[4/7] a prompt past index_topk, and one past a prefill chunk"
MID="In 1905 Albert Einstein published four papers that changed physics: on the photoelectric effect, on Brownian motion, on special relativity."
N=$(ntok "$MID")
[ "$N" -gt 8 ] && ok "the mid prompt is $N tokens (> index_topk 8)" || bad "mid prompt only $N tokens"
parity "mid prompt" "$MID" 12
LONG="In 1905 Albert Einstein published four papers that changed physics: on the photoelectric effect, on Brownian motion, on special relativity, and on the equivalence of mass and energy. Each of them answered a question that had puzzled physicists for years. A century later, the photoelectric effect underlies every digital camera, Brownian motion is the basis of how we model diffusion in cells and markets, and special relativity is corrected for in every GPS receiver. The fourth paper gave us the most famous equation in science, and together they"
N=$(ntok "$LONG")
[ "$N" -gt 64 ] && ok "the long prompt is $N tokens (more than one 64-position chunk)" || bad "long prompt only $N tokens"
parity "long prompt" "$LONG" 8

echo "[5/7] q8_0"
Q="$WORK/tiny-q8_0.gguf"
"$NL" logits "$Q" "$MID" > "$WORK/q8.logits"
"$PY" tests/glm_dsa_ref.py logits "$HF" "$("$NL" tokenize "$Q" "$MID")" > "$WORK/ref.logits" 2>/dev/null
"$PY" - "$WORK" <<'PYEOF' && ok "q8_0: same argmax as transformers, logits within 2% of the span" || bad "q8_0 parity"
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/q8.logits'); b = np.loadtxt(w+'/ref.logits')
span = b.max() - b.min()
d = np.abs(a-b).max()
print("    max delta %.3g (span %.3g)" % (d, span))
assert a.argmax() == b.argmax(), "argmax differs"
assert d < span*0.02, "max delta %g vs span %g" % (d, span)
PYEOF

echo "[6/7] the GLM tokenizer vs HF"
if "$PY" -c 'import tokenizers' >/dev/null 2>&1; then
    for S in "The capital of France is" "café naïve" "中文和English混合" "  two  spaces
and a newline" "x = f(42) + 3.14159;"; do
        O=$("$NL" tokenize "$M" "$S")
        R=$("$PY" -c "import sys;from tokenizers import Tokenizer;t=Tokenizer.from_file(sys.argv[1]);print(' '.join(map(str,t.encode(sys.argv[2], add_special_tokens=False).ids)))" "$TOK/tokenizer.json" "$S")
        [ "$O" = "$R" ] && ok "ids == HF for: $S" || { bad "ids differ for: $S"; echo "    ours: $O"; echo "    hf  : $R"; }
    done
else
    echo "  SKIP (python3 tokenizers)"
fi

echo "[7/7] sampled text through the OpenAI API is UTF-8, streamed or not"
# The random model samples from GLM's byte-level vocabulary, so its tokens
# end characters halfway and start malformed ones: a stream must hold a
# half character back until it is whole, and a malformed byte must reach
# the client as U+FFFD — JSON text is UTF-8 — the same in every piece as in
# the whole reply.
PORT=$(( (RANDOM % 20000) + 25000 ))
NURLLAMA_HOME="$WORK/home" "$NL" serve "$M" --port "$PORT" > "$WORK/serve.log" 2>&1 &
SRV=$!
for _ in $(seq 60); do curl -sf "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break; sleep 0.25; done
"$PY" - "$PORT" "$M" <<'PYEOF' && ok "64-token samples: every event UTF-8 JSON, stream text == reply text" || bad "UTF-8 through the API"
import json, sys, urllib.request
port, model = sys.argv[1], sys.argv[2]
def post(body):
    r = urllib.request.Request("http://127.0.0.1:%s/v1/completions" % port, data=json.dumps(body).encode(),
                               headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(r, timeout=600).read()
held = 0
for seed in range(6):
    b = {"model": model, "prompt": "中文和English混合", "max_tokens": 64, "temperature": 1.5, "seed": seed}
    once = json.loads(post(b).decode("utf-8"))["choices"][0]["text"]
    ev = [e[6:] for e in post(dict(b, stream=True)).decode("utf-8").split("\n\n") if e.strip()]
    assert ev[-1] == "[DONE]"
    pieces = [json.loads(e)["choices"][0]["text"] for e in ev[:-1]]
    assert "".join(pieces) == once, seed
    held += 64 - (len(pieces) - 1)
print("    pieces held back for a whole character: %d" % held)
PYEOF
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null

echo "== nurllama glm-dsa tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
