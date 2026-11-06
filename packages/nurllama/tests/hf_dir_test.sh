#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/hf_dir_test.sh — a Hugging Face checkpoint directory opened
#  directly (src/hfmodel.nu), for several architectures.
#
#  For a tiny random llama (NORM rotary: the q/k lanes are permuted at
#  load), qwen3 (a stated head_dim, per-head q/k norms) and glm_moe_dsa (MLA,
#  DSA, MoE: the routed experts' stacks and MLA's k_b / v_b composed from
#  the checkpoint's tensors) made with HF transformers (tests/hf_ref.py),
#  nurllama run on the DIRECTORY must give transformers' own final-position
#  logits (same argmax and top-5, small delta) and greedy text, with the
#  tokenizer built from tokenizer.json giving HF's ids. Then the same with
#  every attention output and MLP down projection stored as an EXL3 tensor
#  group (exllamav3's format; padded widths included): any architecture's
#  linear may be EXL3.
#
#  Needs python3 with torch + transformers >= 5.15, the GLM-5 tokenizer
#  files (GLM_TOKENIZER_DIR, or NURL_NET_TESTS=1), and for the EXL3 half an
#  exllamav3 tree (EXLLAMAV3, or NURL_NET_TESTS=1).
#
#  Run from the package dir:  ./tests/hf_dir_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
PY="${PYTHON:-python3}"

WORK="$(mktemp -d -t nurllama-hfdir.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

for d in gguf safetensor tokenizer gpu http grad nn gpukit tensor hub nurldb; do
    [ -e "deps/$d" ] || { mkdir -p deps && ln -s "../../$d" "deps/$d"; }
done

if ! "$PY" -c 'import numpy, torch; from transformers import GlmMoeDsaForCausalLM, Qwen3ForCausalLM' >/dev/null 2>&1; then
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

echo "[1/3] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

PROMPT="In 1905 Albert Einstein published four papers that changed physics: on the photoelectric effect, on Brownian motion, on special relativity."

# logits + greedy parity of the checkpoint DIRECTORY against transformers
parity() {
    local label="$1" dir="$2" ids ref_ids ref_txt our_txt
    ids=$("$NL" tokenize "$dir" "$PROMPT")
    hf_ids=$("$PY" -c "import sys;from tokenizers import Tokenizer;t=Tokenizer.from_file(sys.argv[1]);print(' '.join(map(str,t.encode(sys.argv[2],add_special_tokens=False).ids)))" "$dir/tokenizer.json" "$PROMPT")
    [ "$ids" = "$hf_ids" ] && ok "$label: tokenizer.json gives HF's ids" || bad "$label: ids ($ids vs $hf_ids)"
    "$NL" logits "$dir" "$PROMPT" > "$WORK/ours.logits" 2>"$WORK/ours.err"
    "$PY" tests/hf_ref.py logits "$dir" "$ids" > "$WORK/ref.logits" 2>/dev/null
    "$PY" - "$WORK" <<'PYEOF' && ok "$label: logits match transformers (same argmax + top-5)" || { bad "$label: logits"; tail -3 "$WORK/ours.err"; }
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/ours.logits'); b = np.loadtxt(w+'/ref.logits')
span = b.max() - b.min(); d = np.abs(a-b).max()
print("    max delta %.3g (span %.3g)" % (d, span))
assert a.argmax() == b.argmax() and list(np.argsort(-a)[:5]) == list(np.argsort(-b)[:5])
assert d < span*1e-4
PYEOF
    ref_ids=$("$PY" tests/hf_ref.py greedy "$dir" "$ids" 8 2>/dev/null)
    ref_txt=$("$NL" detok "$dir" $ref_ids)
    our_txt=$("$NL" run "$dir" "$PROMPT" -n 8 --temp 0 --ctx 512)
    [ "$our_txt" = "$ref_txt" ] && ok "$label: 8-token greedy text == transformers'" || {
        bad "$label: greedy"; echo "    ours: $our_txt"; echo "    ref : $ref_txt"; }
}

echo "[2/3] checkpoints of three architectures, opened as directories"
for arch in llama qwen3 glm_moe_dsa; do
    d="$WORK/$arch"
    if "$PY" tests/hf_ref.py make "$arch" "$d" "$TOK" >"$WORK/make.log" 2>&1; then parity "$arch" "$d"
    else bad "$arch: make"; tail -3 "$WORK/make.log"; fi
done

echo "[3/3] the same with EXL3 linears in the checkpoint"
if [ -n "$EX" ] && [ -f "$EX/tests/testlib/trellis.py" ]; then
    for arch in llama glm_moe_dsa; do
        d="$WORK/$arch-exl3"
        if "$PY" tests/hf_ref.py make "$arch" "$d" "$TOK" "$EX" >"$WORK/make.log" 2>&1; then parity "$arch + EXL3" "$d"
        else bad "$arch + EXL3: make"; tail -3 "$WORK/make.log"; fi
    done
else
    echo "  SKIP (set EXLLAMAV3 to an exllamav3 source tree, or NURL_NET_TESTS=1)"
fi

echo "== nurllama hf-dir tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
