#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/infer_test.sh — proof of the nurllama inference core.
#
#  Everything here is net-gated (NURL_NET_TESTS=1): the assertions run
#  against real llama.cpp models pulled from HF and an INDEPENDENT
#  numpy implementation of the llama forward pass (tests/llama_ref.py,
#  which reads the GGUF itself — no shared code with the NURL side):
#    1. final-position logits vs numpy: tiny f32 rounding tolerance,
#       identical argmax
#    2. 40-token greedy continuation: TEXT-IDENTICAL to numpy's
#    3. CPU backend (NURL_GPU=cpu) produces the same greedy text as
#       the default backend — kernel parity
#    4. a quantized model (Q4_0+Q8_0) generates coherent text through
#       the host-dequant load path
#    5. sampling: seeded runs are deterministic, seeds differ
#
#  Run from the package dir:  ./tests/infer_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t nurllama-infer.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

[ -e deps/gguf ] || { mkdir -p deps && ln -s ../../gguf deps/gguf; }
[ -e deps/gpu ]  || { mkdir -p deps && ln -s ../../gpu deps/gpu; }

echo "[1/2] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

echo "[2/2] inference vs independent references"
if [ "${NURL_NET_TESTS:-0}" != 1 ] || ! command -v curl >/dev/null 2>&1 \
   || ! python3 -c 'import numpy' >/dev/null 2>&1; then
    echo "  SKIP (set NURL_NET_TESTS=1 with curl + python3-numpy)"
    echo "== nurllama inference tests: PASS=$PASS FAIL=$FAIL"
    exit 0
fi

M="$WORK/stories260K.gguf"
curl -sL --max-time 120 -f -o "$M" \
    https://huggingface.co/ggml-org/models/resolve/main/tinyllamas/stories260K.gguf \
    || { echo "  SKIP download failed"; exit 0; }

PROMPT="Once upon a time"
IDS=$("$NL" tokenize "$M" "$PROMPT")

# 1. logits parity
"$NL" logits "$M" "$PROMPT" > "$WORK/ours.logits"
python3 tests/llama_ref.py "$M" "$IDS" > "$WORK/ref.logits"
python3 - "$WORK" <<'PYEOF' && ok "logits match numpy (f32 tolerance, same argmax)" || bad "logits parity"
import sys, numpy as np
w=sys.argv[1]
a=np.loadtxt(w+'/ours.logits'); b=np.loadtxt(w+'/ref.logits')
rel=np.abs(a-b)/(np.abs(b)+1e-6)
assert a.argmax()==b.argmax(), "argmax differs"
assert rel.max()<1e-3, "max rel %g"%rel.max()
PYEOF

# 2. greedy continuation, text-identical to numpy's
REF_IDS=$(python3 tests/llama_ref.py "$M" "$IDS" greedy 40)
REF_TXT=$("$NL" detok "$M" $REF_IDS)
OUR_TXT=$("$NL" run "$M" "$PROMPT" -n 40 --temp 0)
if [ "$OUR_TXT" = "$REF_TXT" ]; then ok "40-token greedy text == numpy greedy"; else
    bad "greedy parity"; echo "    ours: $OUR_TXT"; echo "    ref : $REF_TXT"; fi

# 3. CPU backend parity
CPU_TXT=$(NURL_GPU=cpu "$NL" run "$M" "$PROMPT" -n 40 --temp 0)
[ "$CPU_TXT" = "$OUR_TXT" ] && ok "CPU backend text == default backend" || bad "backend parity"

# 4. quantized model generates through the dequant load path
MQ="$WORK/stories15Mq.gguf"
if curl -sL --max-time 180 -f -o "$MQ" \
    https://huggingface.co/ggml-org/models/resolve/main/tinyllamas/stories15M-q4_0.gguf; then
    QT=$("$NL" run "$MQ" "$PROMPT" -n 24 --temp 0)
    [ "$(printf '%s' "$QT" | wc -w)" -ge 8 ] && ok "Q4_0+Q8_0 model generates ($(printf '%s' "$QT" | wc -w) words)" || bad "quantized generation"
else
    echo "  SKIP quantized model download failed"
fi

# 5. quantised-native device kernels == the host dequant oracle
MQ2="$WORK/q4km.gguf"
if curl -sL --max-time 240 -f -o "$MQ2" \
    https://huggingface.co/QuantFactory/SmolLM-135M-GGUF/resolve/main/SmolLM-135M.Q4_K_M.gguf; then
    "$NL" logits "$MQ2" "Once upon a time" > "$WORK/dev.logits"
    NURLLAMA_DEQUANT=host "$NL" logits "$MQ2" "Once upon a time" > "$WORK/host.logits"
    python3 - "$WORK" <<'PYEOF3' && ok "device quant kernels == host dequant oracle (Q4_K/Q6_K/Q5_0/Q8_0)" || bad "quant kernel equivalence"
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/dev.logits'); b = np.loadtxt(w+'/host.logits')
span = b.max() - b.min()
assert np.abs(a-b).max() < span*1e-4, "device/host logits diverge"
assert list(np.argsort(-a)[:5]) == list(np.argsort(-b)[:5]), "top-5 differ"
PYEOF3
    QK=$("$NL" run "$MQ2" "Once upon a time" -n 16 --temp 0)
    QH=$(NURLLAMA_DEQUANT=host "$NL" run "$MQ2" "Once upon a time" -n 16 --temp 0)
    [ "$QK" = "$QH" ] && ok "K-quant greedy text identical device-native vs host-dequant" || bad "K-quant text drift"
    QC=$(NURL_GPU=cpu "$NL" run "$MQ2" "Once upon a time" -n 16 --temp 0)
    [ "$QC" = "$QK" ] && ok "K-quant CPU backend text == device text" || bad "K-quant backend parity"
    DEVMEM=$(NURLLAMA_VERBOSE=1 "$NL" run "$MQ2" "hi" -n 1 --temp 0 2>&1 >/dev/null | grep -oP 'device memory: \K[0-9]+')
    HOSTMEM=$(NURLLAMA_VERBOSE=1 NURLLAMA_DEQUANT=host "$NL" run "$MQ2" "hi" -n 1 --temp 0 2>&1 >/dev/null | grep -oP 'device memory: \K[0-9]+')
    [ -n "$DEVMEM" ] && [ -n "$HOSTMEM" ] && [ "$DEVMEM" -lt "$HOSTMEM" ] \
        && ok "quantised weights cut device memory ${HOSTMEM} → ${DEVMEM} MiB" \
        || bad "device memory not reduced ($DEVMEM vs $HOSTMEM)"
else
    echo "  SKIP Q4_K_M download failed"
fi

# 5b. Q5_K / Q6_K native kernels == the host dequant oracle. The Q4_K_M file
# above is mostly Q5_0 + Q4_K; nothing exercised Q5_K until the warp-per-row
# matvecs were written for it, so it gets its own model.
MQ3="$WORK/q5km.gguf"
if curl -sL --max-time 240 -f -o "$MQ3" \
    https://huggingface.co/QuantFactory/SmolLM-135M-GGUF/resolve/main/SmolLM-135M.Q5_K_M.gguf; then
    "$NL" logits "$MQ3" "Once upon a time" > "$WORK/dev5.logits"
    NURLLAMA_DEQUANT=host "$NL" logits "$MQ3" "Once upon a time" > "$WORK/host5.logits"
    python3 - "$WORK" <<'PYEOF5' && ok "device quant kernels == host dequant oracle (Q5_K/Q6_K)" || bad "Q5_K kernel equivalence"
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/dev5.logits'); b = np.loadtxt(w+'/host5.logits')
span = b.max() - b.min()
assert np.abs(a-b).max() < span*1e-4, "device/host logits diverge"
assert list(np.argsort(-a)[:5]) == list(np.argsort(-b)[:5]), "top-5 differ"
PYEOF5
    Q5K=$("$NL" run "$MQ3" "Once upon a time" -n 16 --temp 0)
    Q5H=$(NURLLAMA_DEQUANT=host "$NL" run "$MQ3" "Once upon a time" -n 16 --temp 0)
    [ "$Q5K" = "$Q5H" ] && ok "Q5_K greedy text identical device-native vs host-dequant" || bad "Q5_K text drift"
else
    echo "  SKIP Q5_K_M download failed"
fi

# 5c. gemma3 — a genuinely different shape: embeddings scaled by sqrt(n_embd),
# head_dim decoupled from n_embd/n_head (270m: 640/4 = 160, but head_dim is
# 256), per-head Q/K norms, post-attention and post-FFW norms, GeGLU, and a
# 512-token sliding window on five of every six layers (those layers use their
# own RoPE base). The reference (tests/gemma_ref.py) was itself checked against
# HF transformers running the original safetensors: every layer's hidden state
# to cosine 1.0000, logits r = 0.9996, same top-1.
GM="$WORK/gemma3.gguf"
# 279 MB — the 300 s the smaller models get is not enough, and a truncated
# download silently SKIPs the whole gemma block.
if curl -sL --max-time 1800 -f -o "$GM" \
    https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/main/gemma-3-270m-it-Q8_0.gguf; then
    GIDS=$("$NL" tokenize "$GM" "The capital of France is")
    GREF=$(python3 tests/gemma_ref.py "$GM" "$GIDS" greedy 16)
    GREFTXT=$("$NL" detok "$GM" $GREF)
    GOURS=$("$NL" run "$GM" "The capital of France is" -n 16 --temp 0)
    [ "$GREFTXT" = "$GOURS" ] && ok "gemma3 greedy text == numpy reference (HF-verified)" || {
        bad "gemma3 forward pass"; echo "    ref: [$GREFTXT]"; echo "    our: [$GOURS]"; }
    GCPU=$(NURL_GPU=cpu "$NL" run "$GM" "The capital of France is" -n 16 --temp 0)
    [ "$GCPU" = "$GOURS" ] && ok "gemma3 CPU backend text == device text" || bad "gemma3 backend parity"
    GHOST=$(NURLLAMA_DEQUANT=host "$NL" run "$GM" "The capital of France is" -n 16 --temp 0)
    [ "$GHOST" = "$GOURS" ] && ok "gemma3 host-dequant text == device-native text" || bad "gemma3 dequant parity"

    # The sliding window only engages past 512 tokens, so it takes a long
    # prompt to exercise it at all — and that prompt also crosses the 64-token
    # prefill chunks.
    GLONG=$(python3 -c "print('The quick brown fox jumps over the lazy dog. ' * 70, end='')")
    GLIDS=$("$NL" tokenize "$GM" "$GLONG"); GNP=$(echo $GLIDS | wc -w)
    GLREF=$("$NL" detok "$GM" $(python3 tests/gemma_ref.py "$GM" "$GLIDS" greedy 8))
    GLOURS=$("$NL" run "$GM" "$GLONG" -n 8 --temp 0)
    [ "$GLREF" = "$GLOURS" ] \
        && ok "gemma3 $GNP-token prompt (crosses the 512 sliding window) == reference" \
        || bad "gemma3 sliding window / chunked prefill"

    # A chat template writes its turn markers as TEXT; they have to come back
    # out as single ids or the model answers a prompt it has never seen. These
    # ids are what HF's own tokenizer produces for the same string.
    # No trailing newline in the prompt: `$( )` strips those, so asking for one
    # here would only test the shell.
    printf -v GPROMPT '<start_of_turn>user\nHi there<end_of_turn>\n<start_of_turn>model'
    GT=$("$NL" tokenize "$GM" "$GPROMPT")
    [ "$GT" = "2 105 2364 107 10979 993 106 107 105 4368" ] \
        && ok "gemma3 chat markers tokenise as single special ids (== HF)" \
        || { bad "special-token parsing"; echo "    got: $GT"; }
else
    echo "  SKIP gemma3 download failed"
fi

# 5d. phi3 — the llama shape, but Q/K/V arrive as ONE tensor (attn_qkv, rows
# q|k|v) and the FFN gate and up as one (ffn_up, rows gate|up). Nothing is
# split: a weight is a device pointer plus a row count, so the parts are row
# RANGES inside the uploaded buffer, and every range lands on a block boundary
# because a row is a whole number of quantisation blocks. Getting an offset
# wrong produces garbage immediately, which is exactly what this checks.
#
# The model is 2.4 GB, so this block is opt-in: NURLLAMA_BIG_TESTS=1.
if [ "${NURLLAMA_BIG_TESTS:-0}" = "1" ]; then
    PM="$WORK/phi3.gguf"
    if curl -sL --max-time 3600 -f -o "$PM" \
        https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf; then
        PIDS=$("$NL" tokenize "$PM" "The capital of France is")
        PREF=$("$NL" detok "$PM" $(python3 tests/phi_ref.py "$PM" "$PIDS" greedy 12))
        POURS=$("$NL" run "$PM" "The capital of France is" -n 12 --temp 0)
        [ "$PREF" = "$POURS" ] && ok "phi3 greedy text == numpy reference (fused qkv + fused gate/up)" || {
            bad "phi3 forward pass"; echo "    ref: [$PREF]"; echo "    our: [$POURS]"; }
        PCPU=$(NURL_GPU=cpu "$NL" run "$PM" "The capital of France is" -n 12 --temp 0)
        [ "$PCPU" = "$POURS" ] && ok "phi3 CPU backend text == device text" || bad "phi3 backend parity"
        PHOST=$(NURLLAMA_DEQUANT=host "$NL" run "$PM" "The capital of France is" -n 12 --temp 0)
        [ "$PHOST" = "$POURS" ] && ok "phi3 host-dequant text == device-native text" || bad "phi3 dequant parity"
        printf -v PPROMPT '<|user|>\nHi<|end|>\n<|assistant|>'
        PT=$("$NL" tokenize "$PM" "$PPROMPT")
        [ "$PT" = "1 32010 29871 13 18567 32007 29871 13 32001" ] \
            && ok "phi3 chat markers tokenise as single special ids" \
            || { bad "phi3 special-token parsing"; echo "    got: $PT"; }
    else
        echo "  SKIP phi3 download failed"
    fi
else
    echo "  SKIP phi3 (2.4 GB model — set NURLLAMA_BIG_TESTS=1 to run it)"
fi

# 5e. the safetensors weight source — the same model, out of the container
# Hugging Face ships it in. This is what PROVES packages/safetensor: if the
# reader got a dtype, an offset or a row order wrong, the forward pass says so.
if [ -n "${NURLLAMA_HF_GEMMA_ST:-}" ] && [ -f "$NURLLAMA_HF_GEMMA_ST" ] && [ -f "$WORK/gemma3.gguf" ]; then
    "$NL" logits "$WORK/gemma3.gguf" "The capital of France is" > "$WORK/g_gguf.logits"
    "$NL" logits "$WORK/gemma3.gguf" "The capital of France is" \
        --weights "$NURLLAMA_HF_GEMMA_ST" > "$WORK/g_st.logits"
    python3 - "$WORK" <<'PYEOF6' && ok "safetensors weights are read (and are NOT the GGUF's)" || bad "safetensors weight source"
import sys, numpy as np
w = sys.argv[1]
g = np.loadtxt(w + '/g_gguf.logits')      # our engine, GGUF Q8_0 weights
t = np.loadtxt(w + '/g_st.logits')        # our engine, safetensors bf16 weights
# They must DIFFER — identical logits would mean the safetensors file was never
# read, and this whole check would be passing on the GGUF path.
assert np.abs(g - t).max() > 1e-3, "safetensors path produced the GGUF's logits — it was not used"
# ...and the top-1 must still agree: different precision, same model.
assert np.argmax(g) == np.argmax(t), "the two containers disagree on the model"
PYEOF6
    ST_TXT=$("$NL" run "$WORK/gemma3.gguf" "The capital of France is" -n 16 --temp 0 --weights "$NURLLAMA_HF_GEMMA_ST")
    GG_TXT=$("$NL" run "$WORK/gemma3.gguf" "The capital of France is" -n 16 --temp 0)
    [ "$ST_TXT" = "$GG_TXT" ] \
        && ok "safetensors weights give the same greedy text as the GGUF's" \
        || { bad "safetensors greedy text"; echo "    gguf: [$GG_TXT]"; echo "    st  : [$ST_TXT]"; }
    ST_CPU=$(NURL_GPU=cpu "$NL" run "$WORK/gemma3.gguf" "The capital of France is" -n 16 --temp 0 --weights "$NURLLAMA_HF_GEMMA_ST")
    [ "$ST_CPU" = "$ST_TXT" ] && ok "safetensors weights: CPU backend == device" || bad "safetensors backend parity"
else
    echo "  SKIP safetensors weight source (set NURLLAMA_HF_GEMMA_ST=/path/to/gemma-3-270m/model.safetensors)"
fi

# 6. seeded sampling determinism
A=$("$NL" run "$M" "One day" -n 16 --temp 0.8 --seed 7)
B=$("$NL" run "$M" "One day" -n 16 --temp 0.8 --seed 7)
C=$("$NL" run "$M" "One day" -n 16 --temp 0.8 --seed 8)
[ "$A" = "$B" ] && ok "same seed → same sample" || bad "sampling determinism"
[ "$A" != "$C" ] && ok "different seed → different sample" || bad "seed sensitivity"

# batched prefill: a prompt LONGER than one chunk (64 tokens) must give
# exactly the same continuation the reference does — the chunk boundary is
# where a batching bug hides
LONGP=$(python3 -c "print('The quick brown fox jumps over the lazy dog. ' * 30, end='')")
# tokenise exactly as `run` does (BOS included) so the reference sees the
# same prompt
LIDS=$("$NL" tokenize "$M" "$LONGP")
NP=$(echo $LIDS | wc -w)
LREF=$(python3 tests/llama_ref.py "$M" "$LIDS" greedy 8)
LREFTXT=$("$NL" detok "$M" $LREF)
LOURS=$("$NL" run "$M" "$LONGP" -n 8 --temp 0)
[ "$LREFTXT" = "$LOURS" ] && ok "batched prefill: $NP-token prompt (crosses chunk boundaries) == numpy greedy" || {
    bad "batched prefill"; echo "    ours: $LOURS"; echo "    ref : $LREFTXT"; }

# ── qwen2: a different architecture, tokenizer variant and rotary layout ──
# A 400 MB download per run is unfriendly: point NURLLAMA_TEST_QWEN at an
# already-fetched Qwen2.5 GGUF to reuse it; otherwise it is fetched once.
QW="${NURLLAMA_TEST_QWEN:-}"
if [ -z "$QW" ]; then
    QW="$WORK/qwen.gguf"
    curl -sL --max-time 1800 -f -o "$QW" \
        https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf \
        || rm -f "$QW"
fi
if python3 -c 'import regex' 2>/dev/null && [ -s "$QW" ]; then
    # token ids vs an independent BPE reference that reads the model's own
    # vocab, merges and tokenizer.ggml.pre and applies llama.cpp's regex
    QP=0; QF=0
    while IFS= read -r t; do
        ours=$("$NL" tokenize "$QW" "$t" --no-special)
        ref=$(printf '%s' "$t" | python3 tests/bpe_ref.py "$QW")
        if [ "$ours" = "$ref" ]; then QP=$((QP+1)); else QF=$((QF+1)); echo "    MISMATCH [$t]"; fi
    done <<'STRINGS'
Hello world
The year 2025 had 365 days
def foo(x): return x+1
  spaces   and tabs
café naïve 日本語
It's John's, isn't IT?
1234567890
(parens) [brackets]
STRINGS
    [ "$QF" = 0 ] && ok "qwen2 tokenizer: $QP strings match the independent BPE reference" || bad "qwen2 tokenizer ($QF mismatches)"

    QIDS=$("$NL" tokenize "$QW" "The capital of France is" --no-special)
    "$NL" logits "$QW" "The capital of France is" > "$WORK/q_ours.logits"
    python3 tests/llama_ref.py "$QW" "$QIDS" > "$WORK/q_ref.logits"
    python3 - "$WORK" <<'PYEOF2' && ok "qwen2 logits match the independent numpy forward pass" || bad "qwen2 logits"
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/q_ours.logits'); b = np.loadtxt(w+'/q_ref.logits')
span = b.max() - b.min()
assert np.abs(a-b).max() < span*1e-4, "logits diverge"
assert list(np.argsort(-a)[:5]) == list(np.argsort(-b)[:5]), "top-5 differ"
PYEOF2
    QREF=$(python3 tests/llama_ref.py "$QW" "$QIDS" greedy 12)
    QREFTXT=$("$NL" detok "$QW" $QREF)
    QOURS=$("$NL" run "$QW" "The capital of France is" -n 12 --temp 0)
    [ "$QREFTXT" = "$QOURS" ] && ok "qwen2 greedy text == numpy greedy (biases + NEOX rotary)" || {
        bad "qwen2 greedy"; echo "    ours: $QOURS"; echo "    ref : $QREFTXT"; }
    QCPU=$(NURL_GPU=cpu "$NL" run "$QW" "The capital of France is" -n 12 --temp 0)
    [ "$QCPU" = "$QOURS" ] && ok "qwen2 CPU backend text == device text" || bad "qwen2 backend parity"
else
    echo "  SKIP qwen2 (needs python3-regex and the model)"
fi

echo "== nurllama inference tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
