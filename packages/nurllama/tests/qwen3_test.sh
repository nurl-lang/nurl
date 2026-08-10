#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/qwen3_test.sh — proof of the qwen3 architecture.
#
#  qwen3 is the llama shape with four differences, every one of which is
#  SILENT when wrong (the model still runs, still emits fluent text):
#    · NEOX rotary rather than adjacent-lane NORM
#    · no Q/K/V bias
#    · head_dim is stated (attention.key_length), so n_head·head_dim need
#      not equal n_embd — Qwen3-0.6B is 16×128 = 2048 against 1024
#    · a per-head RMSNorm on Q and K before the rotation
#
#  So the assertions here are against an INDEPENDENT numpy implementation
#  that reads the same GGUF and shares no code with the NURL side
#  (tests/qwen3_ref.py):
#    1. final-position logits: same argmax, same top-5, delta small
#       against the logit span
#    2. 20-token greedy continuation: TEXT-IDENTICAL to numpy's
#
#  Set QWEN3_GGUF to skip the download. Otherwise net-gated
#  (NURL_NET_TESTS=1) — the model is ~610 MB.
#
#  Run from the package dir:  ./tests/qwen3_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t nurllama-qwen3.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

[ -e deps/gguf ] || { mkdir -p deps && ln -s ../../gguf deps/gguf; }
[ -e deps/gpu ]  || { mkdir -p deps && ln -s ../../gpu deps/gpu; }

if ! python3 -c 'import numpy' >/dev/null 2>&1; then
    echo "  SKIP (python3-numpy required)"; exit 0
fi

M="${QWEN3_GGUF:-}"
if [ -z "$M" ]; then
    if [ "${NURL_NET_TESTS:-0}" != 1 ] || ! command -v curl >/dev/null 2>&1; then
        echo "  SKIP (set QWEN3_GGUF, or NURL_NET_TESTS=1 with curl)"; exit 0
    fi
    M="$WORK/qwen3-0.6b.gguf"
    curl -sL --max-time 900 -f -o "$M" \
        https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf \
        || { echo "  SKIP download failed"; exit 0; }
fi
[ -f "$M" ] || { echo "  SKIP model not found: $M"; exit 0; }

echo "[1/2] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

echo "[2/2] qwen3 vs the independent numpy reference"
PROMPT="The capital of France is"
IDS=$("$NL" tokenize "$M" "$PROMPT")

"$NL" logits "$M" "$PROMPT" > "$WORK/ours.logits"
python3 tests/qwen3_ref.py "$M" "$IDS" > "$WORK/ref.logits"
python3 - "$WORK" <<'PYEOF' && ok "logits match numpy (same argmax + top-5)" || bad "logits parity"
import sys, numpy as np
w = sys.argv[1]
a = np.loadtxt(w+'/ours.logits'); b = np.loadtxt(w+'/ref.logits')
span = b.max() - b.min()
assert a.argmax() == b.argmax(), "argmax differs"
assert list(np.argsort(-a)[:5]) == list(np.argsort(-b)[:5]), "top-5 differ"
assert np.abs(a-b).max() < span*1e-4, "max delta %g vs span %g" % (np.abs(a-b).max(), span)
PYEOF

REF_IDS=$(python3 tests/qwen3_ref.py "$M" "$IDS" greedy 20)
REF_TXT=$("$NL" detok "$M" $REF_IDS)
OUR_TXT=$("$NL" run "$M" "$PROMPT" -n 20 --temp 0 --ctx 512)
if [ "$OUR_TXT" = "$REF_TXT" ]; then ok "20-token greedy text == numpy greedy"; else
    bad "greedy parity"; echo "    ours: $OUR_TXT"; echo "    ref : $REF_TXT"; fi

echo "== nurllama qwen3 tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
