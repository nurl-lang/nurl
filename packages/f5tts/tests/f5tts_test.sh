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

echo "== the quality gate's ears =="
if build verify_test; then
  if "$WORK/verify_test" >"$WORK/verify.out" 2>&1; then
    ok "word errors: numbers, hyphens, compounds; the opening-sentence rule"
  else
    bad "word errors"; grep -v "^  ok" "$WORK/verify.out" | tail -20
  fi
else
  bad "verify_test does not build"
fi

CKPT="${F5TTS_CKPT:-}"
VOCAB="${F5TTS_VOCAB:-}"
VOCODER="${F5TTS_VOCODER:-}"

echo "== how a model name is read =="
if build name_test && "$WORK/name_test" >"$WORK/name.out" 2>&1; then
  ok "references, local names, and the vocabulary derived from each"
else
  bad "model-name resolution"; cat "$WORK/name.out"
fi

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
  # The dump says what it was made with. Taking these from a default instead
  # compares the right waveform against the wrong scale: the reference
  # normalises the recording to an rms of 0.1 and scales the result back by
  # the recording's own rms afterwards, so guessing that number wrong shifts
  # the whole waveform by a constant and the test reports a broken vocoder.
  meta_num() { sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*\([0-9.eE+-]*\).*/\1/p' "$F5TTS_REF_GEN/meta.json" 2>/dev/null | head -1; }
  REF_LEN="${F5TTS_REF_LEN:-$(meta_num ref_audio_len)}"; : "${REF_LEN:=1021}"
  REF_NFE="${F5TTS_REF_NFE:-$(meta_num nfe)}";           : "${REF_NFE:=32}"
  REF_RMS="${F5TTS_REF_RMS:-$(meta_num rms)}";           : "${REF_RMS:=0.1}"
  if build gen_test && "$WORK/gen_test" "$CKPT" "$VOCAB" "$VOCODER" "$F5TTS_REF_GEN" \
       "$REF_LEN" "$REF_NFE" "$REF_RMS" \
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
