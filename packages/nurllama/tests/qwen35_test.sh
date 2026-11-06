#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/qwen35_test.sh — proof of the qwen35 architecture (Qwen3.5 and
#  Qwen3.8: `model_type qwen3_5`).
#
#  qwen35 is a hybrid: three layers of every four are Gated DeltaNet —
#  a causal conv and a recurrent state that carries every position seen
#  so far — and the fourth is full attention with an output gate and a
#  partial rotary. Getting any of it wrong still produces fluent text,
#  so the assertions are against an INDEPENDENT numpy implementation that
#  reads the same GGUF and shares no code with the NURL side
#  (tests/qwen35_ref.py, itself checked against HF transformers by
#  tests/qwen35_hf_check.py):
#    1. final-position logits: same argmax, same top-5, delta small
#       against the logit span
#    2. 20-token greedy continuation: TEXT-IDENTICAL to numpy's
#    3. a prompt longer than one prefill chunk (64 positions): the conv
#       and recurrent states carry across the chunk boundary and on into
#       decoding — logits and a 16-token greedy continuation
#    4. (with python3 `tokenizers` and QWEN35_TOKENIZER=tokenizer.json)
#       the qwen35 pre-split — letters with combining marks in the word
#       class — gives HF's ids
#
#  Set QWEN35_GGUF to skip the download. Otherwise net-gated
#  (NURL_NET_TESTS=1) — Qwen3.5-0.8B Q8_0 is ~830 MB.
#
#  Run from the package dir:  ./tests/qwen35_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
PY="${PYTHON:-python3}"

WORK="$(mktemp -d -t nurllama-qwen35.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

for d in gguf safetensor tokenizer gpu http grad nn gpukit tensor hub nurldb; do
    [ -e "deps/$d" ] || { mkdir -p deps && ln -s "../../$d" "deps/$d"; }
done

if ! "$PY" -c 'import numpy' >/dev/null 2>&1; then
    echo "  SKIP (python3-numpy required)"; exit 0
fi

M="${QWEN35_GGUF:-}"
if [ -z "$M" ]; then
    if [ "${NURL_NET_TESTS:-0}" != 1 ] || ! command -v curl >/dev/null 2>&1; then
        echo "  SKIP (set QWEN35_GGUF, or NURL_NET_TESTS=1 with curl)"; exit 0
    fi
    M="$WORK/qwen3.5-0.8b.gguf"
    curl -sL --max-time 1800 -f -o "$M" \
        https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q8_0.gguf \
        || { echo "  SKIP download failed"; exit 0; }
fi
[ -f "$M" ] || { echo "  SKIP model not found: $M"; exit 0; }

echo "[1/4] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

# logits + greedy parity for one prompt
parity() {
    local label="$1" prompt="$2" n="$3"
    local ids ref_ids ref_txt our_txt
    ids=$("$NL" tokenize "$M" "$prompt")
    "$NL" logits "$M" "$prompt" > "$WORK/ours.logits"
    "$PY" tests/qwen35_ref.py "$M" "$ids" > "$WORK/ref.logits"
    "$PY" - "$WORK" <<'PYEOF' && ok "$label: logits match numpy (same argmax + top-5)" || bad "$label: logits parity"
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/ours.logits'); b = np.loadtxt(w+'/ref.logits')
span = b.max() - b.min()
assert a.argmax() == b.argmax(), "argmax differs"
assert list(np.argsort(-a)[:5]) == list(np.argsort(-b)[:5]), "top-5 differ"
assert np.abs(a-b).max() < span*1e-4, "max delta %g vs span %g" % (np.abs(a-b).max(), span)
PYEOF
    ref_ids=$("$PY" tests/qwen35_ref.py "$M" "$ids" greedy "$n")
    ref_txt=$("$NL" detok "$M" $ref_ids)
    our_txt=$("$NL" run "$M" "$prompt" -n "$n" --temp 0 --ctx 512)
    if [ "$our_txt" = "$ref_txt" ]; then ok "$label: $n-token greedy text == numpy greedy"; else
        bad "$label: greedy parity"; echo "    ours: $our_txt"; echo "    ref : $ref_txt"; fi
}

echo "[2/4] qwen35 vs the independent numpy reference"
parity "short prompt" "The capital of France is" 20

echo "[3/4] across a prefill chunk, then decoding"
LONG="In 1905 Albert Einstein published four papers that changed physics: on the photoelectric effect, on Brownian motion, on special relativity, and on the equivalence of mass and energy. Each of them answered a question that had puzzled physicists for years. A century later, the photoelectric effect underlies every digital camera, Brownian motion is the basis of how we model diffusion in cells and markets, and special relativity is corrected for in every GPS receiver. The fourth paper gave us the most famous equation in science, and together they"
NTOK=$("$NL" tokenize "$M" "$LONG" | wc -w)
[ "$NTOK" -gt 64 ] && ok "the long prompt is $NTOK tokens (more than one 64-position chunk)" || bad "long prompt only $NTOK tokens"
parity "long prompt" "$LONG" 16

echo "[4/4] the qwen35 pre-split vs HF tokenizers"
if [ -n "${QWEN35_TOKENIZER:-}" ] && "$PY" -c 'import tokenizers' >/dev/null 2>&1; then
    for S in "The capital of France is" "café naïve" "हिन्दी भाषा" "Ελληνικά καὶ Ἀθῆναι" "ﾃｽﾄ (§«q»½) ١٢٣" "  two  spaces
and a newline"; do
        O=$("$NL" tokenize "$M" "$S")
        R=$("$PY" -c "import sys;from tokenizers import Tokenizer;t=Tokenizer.from_file(sys.argv[1]);print(' '.join(map(str,t.encode(sys.argv[2]).ids)))" "$QWEN35_TOKENIZER" "$S")
        [ "$O" = "$R" ] && ok "ids == HF for: $S" || { bad "ids differ for: $S"; echo "    ours: $O"; echo "    hf  : $R"; }
    done
else
    echo "  SKIP (set QWEN35_TOKENIZER=/path/to/tokenizer.json, with python3 tokenizers)"
fi

echo "== nurllama qwen35 tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
