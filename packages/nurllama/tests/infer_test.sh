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

# 6. seeded sampling determinism
A=$("$NL" run "$M" "One day" -n 16 --temp 0.8 --seed 7)
B=$("$NL" run "$M" "One day" -n 16 --temp 0.8 --seed 7)
C=$("$NL" run "$M" "One day" -n 16 --temp 0.8 --seed 8)
[ "$A" = "$B" ] && ok "same seed → same sample" || bad "sampling determinism"
[ "$A" != "$C" ] && ok "different seed → different sample" || bad "seed sensitivity"

echo "== nurllama inference tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
