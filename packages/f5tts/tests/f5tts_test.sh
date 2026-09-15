#!/bin/sh
# ============================================================
#  packages/f5tts — test suite
#
#  1. text_test    the front-end, self-contained: no model, no GPU. Every
#                  expectation came from the reference implementation
#                  (rjieba + convert_char_to_pinyin) and is checked against a
#                  vocabulary the test writes itself.
#
#  The rest need a checkpoint and a card, and compare against tensors dumped
#  from PyTorch by tests/ref_dit.py and tests/ref_gen.py. Point them at a
#  checkpoint and a dump directory and they run:
#
#    F5TTS_CKPT=/path/model.safetensors  F5TTS_VOCAB=/path/vocab.txt
#    F5TTS_VOCODER=/path/pytorch_model.bin
#    F5TTS_REF_DIT=/path/dumped-by-ref_dit.py
#    F5TTS_REF_GEN=/path/dumped-by-ref_gen.py
#    F5TTS_REF_LEN=1021 F5TTS_REF_NFE=32 F5TTS_REF_RMS=0.0695163
#
#  2. dit_test     the text encoder and the 22-block forward, one fixed input
#  3. step_test    the two halves of a guided step, conditional and not
#  4. gen_test     32 ODE steps and the vocoder, from the same noise
#
#  Run from the package dir:  ./tests/f5tts_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t f5tts.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP $1"; SKIP=$((SKIP+1)); }

build() {
  if "$NURL" "tests/$1.nu" "$WORK/$1" >"$WORK/$1.build" 2>&1; then return 0; fi
  echo "--- build of tests/$1.nu failed ---"; tail -20 "$WORK/$1.build"; return 1
}

echo "== the text front-end =="
if build text_test; then
  if "$WORK/text_test" "$WORK" >"$WORK/text.out" 2>&1; then
    ok "characters and chunking, against the reference front-end"
  else
    bad "characters and chunking"; tail -20 "$WORK/text.out"
  fi
else
  bad "text_test does not build"
fi

CKPT="${F5TTS_CKPT:-}"
VOCAB="${F5TTS_VOCAB:-}"
VOCODER="${F5TTS_VOCODER:-}"

echo "== the transformer, against PyTorch =="
if [ -n "$CKPT" ] && [ -n "$VOCAB" ] && [ -n "${F5TTS_REF_DIT:-}" ]; then
  if build dit_test && "$WORK/dit_test" "$CKPT" "$VOCAB" "$F5TTS_REF_DIT" >"$WORK/dit.out" 2>&1; then
    ok "text encoder and the 22-block forward"
  else
    bad "the forward"; tail -20 "$WORK/dit.out"
  fi
else
  skip "no checkpoint or no dump (F5TTS_CKPT, F5TTS_VOCAB, F5TTS_REF_DIT)"
fi

echo "== one guided step =="
if [ -n "$CKPT" ] && [ -n "$VOCAB" ] && [ -n "${F5TTS_REF_GEN:-}" ]; then
  if build step_test && "$WORK/step_test" "$CKPT" "$VOCAB" "$F5TTS_REF_GEN" >"$WORK/step.out" 2>&1; then
    ok "the conditional and unconditional halves"
  else
    bad "classifier-free guidance"; tail -20 "$WORK/step.out"
  fi
else
  skip "no checkpoint or no dump (F5TTS_REF_GEN)"
fi

echo "== the whole pipeline =="
if [ -n "$CKPT" ] && [ -n "$VOCAB" ] && [ -n "$VOCODER" ] && [ -n "${F5TTS_REF_GEN:-}" ]; then
  if build gen_test && "$WORK/gen_test" "$CKPT" "$VOCAB" "$VOCODER" "$F5TTS_REF_GEN" \
       "${F5TTS_REF_LEN:-1021}" "${F5TTS_REF_NFE:-32}" "${F5TTS_REF_RMS:-0.1}" \
       >"$WORK/gen.out" 2>&1; then
    ok "the integrated mel and the waveform"
    grep -E "took" "$WORK/gen.out" | sed 's/^/    /'
  else
    bad "sampling or the vocoder"; tail -20 "$WORK/gen.out"
  fi
else
  skip "no checkpoint, vocoder or dump"
fi

echo
echo "passed $PASS, failed $FAIL, skipped $SKIP"
[ "$FAIL" -eq 0 ]
