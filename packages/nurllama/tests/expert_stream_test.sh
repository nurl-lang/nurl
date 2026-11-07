#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/expert_stream_test.sh — a Mixture of Experts' routed experts
#  streamed from their file (src/experts.nu, Agora #521).
#
#  When the experts do not fit the device, nurllama keeps a few of them
#  there — the expert cache — and loads the ones the router picks on
#  demand. The slots hold an expert as the all-resident stack does and the
#  same kernels run over them, so the claim is exact: with any number of
#  slots (NURLLAMA_EXPERT_SLOTS, down to ONE, where a prefill chunk's
#  experts go through in rounds) the logits and the greedy text are those
#  of the all-resident run, BYTE for byte — for every way experts are held:
#    1. a GGUF's stacks (tiny glm-dsa via llama.cpp's converter): f32 and
#       q8_0 (the batched expert matvec), f16 (one matvec per position and
#       expert) and bf16 (dequantised to f32 at load)
#    2. a checkpoint directory's per-expert tensors
#    3. a checkpoint directory's EXL3 experts (3 bits, MCG — fiore-lab's
#       banks), whole, and cut into tensor-parallel shares by whole tiles
#       (the shares joined back are the whole matrix: the same logits), and
#       the shares in a bank directory of their own (--weights): the same
#       again; and transformers on the decoded weights agrees
#    4. llada2 (a diffusion MoE, every position's logits): f32 and q8_0
#    5. NURLLAMA_EXPERT_CACHE (MiB) streams too
#  The prompt is longer than one prefill chunk (64 positions).
#
#  Needs python3 with torch + transformers >= 5.15, the GLM-5 tokenizer
#  files (GLM_TOKENIZER_DIR, or NURL_NET_TESTS=1); part 1 llama.cpp's
#  converter (LLAMA_CPP), part 3 an exllamav3 tree (EXLLAMAV3, or
#  NURL_NET_TESTS=1). A part without what it needs SKIPs.
#
#  Run from the package dir:  ./tests/expert_stream_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
PY="${PYTHON:-python3}"

WORK="$(mktemp -d -t nurllama-xstream.XXXXXX)"
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
TOK="${GLM_TOKENIZER_DIR:-}"
if [ -z "$TOK" ]; then
    if [ "${NURL_NET_TESTS:-0}" != 1 ]; then echo "  SKIP (set GLM_TOKENIZER_DIR, or NURL_NET_TESTS=1)"; exit 0; fi
    TOK="$WORK/tok"; mkdir -p "$TOK"
    for f in tokenizer.json tokenizer_config.json chat_template.jinja; do
        curl -sfL --max-time 600 -o "$TOK/$f" "https://huggingface.co/zai-org/GLM-5.3/resolve/main/$f" \
            || { echo "  SKIP tokenizer download failed"; exit 0; }
    done
fi
EX="${EXLLAMAV3:-}"
if [ -z "$EX" ] && [ "${NURL_NET_TESTS:-0}" = 1 ]; then
    EX="$WORK/exllamav3"; git clone -q --depth 1 https://github.com/turboderp-org/exllamav3 "$EX" 2>/dev/null || EX=""
fi

echo "[1/6] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

PROMPT="In 1905 Albert Einstein published four papers that changed physics: on the photoelectric effect, on Brownian motion, on special relativity, and on the equivalence of mass and energy. Each of them answered a question that had puzzled physicists for years. A century later, the photoelectric effect underlies every digital camera, and Brownian motion is the basis of how we model diffusion in cells and markets."

# Streamed == resident, byte for byte: logits, then 12 greedy tokens.
# (extra arguments: more `nurllama` options, e.g. --weights)
same() {
    local label="$1" model="$2"; shift 2
    "$NL" logits "$model" "$PROMPT" "$@" > "$WORK/all.logits" 2>"$WORK/all.err" || { bad "$label: resident run"; tail -3 "$WORK/all.err"; return; }
    "$NL" run "$model" "$PROMPT" -n 12 --temp 0 --ctx 512 "$@" > "$WORK/all.txt" 2>/dev/null
    local s good=1 why=""
    for s in 8 3 1; do
        NURLLAMA_EXPERT_SLOTS=$s "$NL" logits "$model" "$PROMPT" "$@" > "$WORK/s.logits" 2>"$WORK/s.err"
        cmp -s "$WORK/all.logits" "$WORK/s.logits" || { good=0; why="$why logits@$s"; tail -2 "$WORK/s.err"; }
    done
    NURLLAMA_EXPERT_SLOTS=3 "$NL" run "$model" "$PROMPT" -n 12 --temp 0 --ctx 512 "$@" > "$WORK/s.txt" 2>/dev/null
    cmp -s "$WORK/all.txt" "$WORK/s.txt" || { good=0; why="$why greedy@3"; }
    [ "$good" = 1 ] && ok "$label: 8, 3 and 1 slots == all resident (logits + 12 greedy tokens, byte for byte)" \
        || bad "$label: streamed differs ($why)"
}

echo "[2/6] a GGUF's expert stacks"
if [ -n "${LLAMA_CPP:-}" ] && [ -f "$LLAMA_CPP/convert_hf_to_gguf.py" ]; then
    HF="$WORK/hf"
    if "$PY" tests/glm_dsa_ref.py make "$HF" "$TOK" >"$WORK/make.log" 2>&1; then
        for t in f32 q8_0 f16 bf16; do
            if "$PY" "$LLAMA_CPP/convert_hf_to_gguf.py" "$HF" --outtype "$t" --outfile "$WORK/tiny-$t.gguf" >"$WORK/conv.log" 2>&1; then
                same "GGUF $t" "$WORK/tiny-$t.gguf"
            else bad "llama.cpp could not convert ($t)"; tail -3 "$WORK/conv.log"; fi
        done
    else bad "could not make the checkpoint"; tail -3 "$WORK/make.log"; fi
else
    echo "  SKIP (set LLAMA_CPP to a llama.cpp source tree, for its converter)"
fi

echo "[3/6] a checkpoint directory's experts"
D="$WORK/glm"
if "$PY" tests/hf_ref.py make glm_moe_dsa "$D" "$TOK" >"$WORK/make.log" 2>&1; then
    same "checkpoint (per-expert tensors)" "$D"
else bad "checkpoint: make"; tail -3 "$WORK/make.log"; fi

echo "[4/6] EXL3 experts: whole, in shares, in a bank of their own"
if [ -n "$EX" ] && [ -f "$EX/tests/testlib/trellis.py" ]; then
    made=1
    "$PY" tests/hf_ref.py make-experts "$WORK/x1" "$TOK" "$EX" 1 >"$WORK/m1.log" 2>&1 || made=0
    "$PY" tests/hf_ref.py make-experts "$WORK/x2" "$TOK" "$EX" 2 >"$WORK/m2.log" 2>&1 || made=0
    "$PY" tests/hf_ref.py make-experts "$WORK/x2b" "$TOK" "$EX" 2 "$WORK/bank" >"$WORK/m3.log" 2>&1 || made=0
    if [ "$made" = 1 ]; then
        same "EXL3 experts, whole" "$WORK/x1"
        same "EXL3 experts, 2 shares" "$WORK/x2"
        same "EXL3 experts, 2 shares in a bank directory" "$WORK/x2b" --weights "$WORK/bank"
        "$NL" logits "$WORK/x1" "$PROMPT" > "$WORK/x1.logits" 2>/dev/null
        "$NL" logits "$WORK/x2" "$PROMPT" > "$WORK/x2.logits" 2>/dev/null
        "$NL" logits "$WORK/x2b" "$PROMPT" --weights "$WORK/bank" > "$WORK/x2b.logits" 2>/dev/null
        cmp -s "$WORK/x1.logits" "$WORK/x2.logits" && cmp -s "$WORK/x1.logits" "$WORK/x2b.logits" \
            && ok "the shares joined back are the whole experts: the same logits, banked or not" \
            || bad "shares / bank give other logits than the whole experts"
        ids=$("$NL" tokenize "$WORK/x1" "$PROMPT")
        "$PY" tests/hf_ref.py logits "$WORK/x1" "$ids" > "$WORK/ref.logits" 2>/dev/null
        "$PY" - "$WORK" <<'PYEOF' && ok "EXL3 experts: logits match transformers on the decoded weights (same argmax + top-5)" || bad "EXL3 experts: transformers parity"
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/x2.logits'); b = np.loadtxt(w+'/ref.logits')
span = b.max() - b.min(); d = np.abs(a-b).max()
print("    max delta %.3g (span %.3g)" % (d, span))
assert a.argmax() == b.argmax() and list(np.argsort(-a)[:5]) == list(np.argsort(-b)[:5])
assert d < span*1e-4
PYEOF
    else bad "EXL3 experts: make"; tail -3 "$WORK/m1.log" "$WORK/m2.log" "$WORK/m3.log"; fi
else
    echo "  SKIP (set EXLLAMAV3 to an exllamav3 source tree, or NURL_NET_TESTS=1)"
fi

echo "[5/6] llada2: a diffusion MoE, every position's logits"
mkdir -p "$WORK/ll"
if "$PY" tests/make_tiny_llada2.py "$WORK/ll" >/dev/null 2>&1     && "$NL" convert "$WORK/ll" "$WORK/ll-f32.gguf" --type f32 >/dev/null 2>&1     && "$NL" convert "$WORK/ll" "$WORK/ll-q8.gguf" >/dev/null 2>&1; then
    IDS="5 12 7 200 33 150 299 0"
    for t in f32 q8; do
        "$NL" dlogits "$WORK/ll-$t.gguf" $IDS > "$WORK/ll.all" 2>/dev/null
        good=1
        for s in 3 1; do
            NURLLAMA_EXPERT_SLOTS=$s "$NL" dlogits "$WORK/ll-$t.gguf" $IDS > "$WORK/ll.s" 2>/dev/null
            [ -s "$WORK/ll.all" ] && cmp -s "$WORK/ll.all" "$WORK/ll.s" || good=0
        done
        [ "$good" = 1 ] && ok "llada2 $t: 3 and 1 slots == all resident (every position's logits, byte for byte)"             || bad "llada2 $t: streamed differs"
    done
else bad "llada2: make / convert"; fi

echo "[6/6] NURLLAMA_EXPERT_CACHE (MiB)"
if [ -d "$D" ]; then
    "$NL" logits "$D" "$PROMPT" > "$WORK/all.logits" 2>/dev/null
    NURLLAMA_VERBOSE=1 NURLLAMA_EXPERT_CACHE=1 "$NL" logits "$D" "$PROMPT" > "$WORK/c.logits" 2>"$WORK/c.err"
    if grep -q "routed experts: [0-9]* of [0-9]* on the device" "$WORK/c.err" && cmp -s "$WORK/all.logits" "$WORK/c.logits"; then
        ok "a 1 MiB cache streams them ($(grep -o 'routed experts: [0-9]* of [0-9]*' "$WORK/c.err")), same logits"
    else bad "NURLLAMA_EXPERT_CACHE"; tail -3 "$WORK/c.err"; fi
fi

echo "== nurllama expert-stream tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
