#!/bin/sh
# ============================================================
#  packages/whisper — test suite (encoder stage)
#
#  The encoder is checked against an independent numpy reference reading the
#  same checkpoint — and that reference is itself checked against HF's
#  WhisperModel.encoder, so a shared misconception cannot hide between the two.
#  That is how the positional-embedding bug was found: the reference agreed with
#  HF, and the kernels agreed with neither.
#
#  Run from the package dir:  ./tests/whisper_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t whisper.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/3] build"
if ! $NURL src/main.nu "$WORK/whisper" >/dev/null 2>"$WORK/build.err"; then
    echo "  build FAILED"; cat "$WORK/build.err"; exit 1
fi
WH="$WORK/whisper"
(cd ../audio && $NURL src/main.nu "$WORK/audio" >/dev/null 2>&1)

echo "[2/3] whisper-tiny + a test clip"
if ! curl -sL --max-time 900 -f -o "$WORK/model.safetensors" \
    https://huggingface.co/openai/whisper-tiny/resolve/main/model.safetensors \
   || ! curl -sL --max-time 120 -f -o "$WORK/config.json" \
    https://huggingface.co/openai/whisper-tiny/resolve/main/config.json; then
    echo "  SKIP (model download failed)"
    echo "== whisper tests: PASS=$PASS FAIL=$FAIL"
    exit 0
fi
python3 - "$WORK" <<'PYEOF'
import sys, numpy as np, wave, struct
W = sys.argv[1]; sr = 16000
t = np.arange(3 * sr) / sr
rng = np.random.RandomState(7)
x = 0.4*np.sin(2*np.pi*220*t)*(1 + 0.5*np.sin(2*np.pi*3*t))
x += 0.25*np.sin(2*np.pi*880*t + 2*np.sin(2*np.pi*5*t))
x += 0.15*np.sin(2*np.pi*2400*t) + 0.05*rng.randn(t.size)
x = x / np.abs(x).max() * 0.9
w = wave.open(W + '/clip.wav', 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(b''.join(struct.pack('<h', int(v * 32767)) for v in x)); w.close()
PYEOF

echo "[3/3] the encoder, against numpy and across both backends"
if "$WH" encode "$WORK/config.json" "$WORK/model.safetensors" "$WORK/clip.wav" \
        -o "$WORK/enc_gpu.f32" >/dev/null 2>&1; then
    ok "the encoder runs end to end (WAV → mel → 1500 x 384 states)"
else
    bad "encoder run"
fi

# the reference gets the mel from our own audio package, so both see one input
"$WORK/audio" mel "$WORK/clip.wav" -o "$WORK/mel.f32" >/dev/null 2>&1
python3 tests/encoder_ref.py "$WORK/model.safetensors" "$WORK/mel.f32" "$WORK/enc_ref.f32" 4 6 80

python3 - "$WORK" <<'PYEOF' && ok "encoder states == independent numpy reference (which matches HF)" || bad "encoder vs numpy"
import sys, numpy as np
W = sys.argv[1]
ours = np.fromfile(W + '/enc_gpu.f32', dtype='<f4')
ref  = np.fromfile(W + '/enc_ref.f32', dtype='<f4')
assert ours.shape == ref.shape, f"{ours.shape} != {ref.shape}"
d = np.abs(ours - ref).max()
r = np.corrcoef(ours, ref)[0, 1]
# f32 kernels against a float64 reference, through 4 layers of 1500x1500
# attention: 1e-3 is accumulation order, and the correlation is what pins the
# answer — a structural bug (like the positional embedding) sends r to 0.004.
assert r > 0.999999, f"correlation {r:.8f}"
assert d < 5e-2, f"max|delta| = {d:.3e}"
print(f"    max|delta| = {d:.3e}, r = {r:.8f}")
PYEOF

if NURL_GPU=cpu "$WH" encode "$WORK/config.json" "$WORK/model.safetensors" "$WORK/clip.wav" \
        -o "$WORK/enc_cpu.f32" >/dev/null 2>&1; then
    python3 - "$WORK" <<'PYEOF' && ok "CPU/OpenMP backend == CUDA backend (the portable matvec agrees with the warp one)" || bad "backend parity"
import sys, numpy as np
W = sys.argv[1]
g = np.fromfile(W + '/enc_gpu.f32', dtype='<f4')
c = np.fromfile(W + '/enc_cpu.f32', dtype='<f4')
d = np.abs(g - c).max()
assert d < 5e-2, f"max|delta| = {d:.3e}"
PYEOF
else
    bad "CPU backend run"
fi

# ── the whole thing: real speech, in and out ────────────────────────
if curl -sL --max-time 120 -f -o "$WORK/tokenizer.json" \
    https://huggingface.co/openai/whisper-tiny/resolve/main/tokenizer.json \
   && curl -sL --max-time 180 -f -o "$WORK/jfk.wav" \
    https://github.com/ggerganov/whisper.cpp/raw/master/samples/jfk.wav; then

    mkdir -p "$WORK/model"
    cp "$WORK/config.json" "$WORK/tokenizer.json" "$WORK/model/"
    cp "$WORK/model.safetensors" "$WORK/model/"

    WANT=" And so my fellow Americans ask not what your country can do for you ask what you can do for your country."
    GOT=$("$WH" transcribe "$WORK/model" "$WORK/jfk.wav" 2>/dev/null)
    [ "$GOT" = "$WANT" ] \
        && ok "real speech transcribes word-for-word as HF transformers does" \
        || { bad "transcription"; echo "    got:  [$GOT]"; echo "    want: [$WANT]"; }

    GOT_CPU=$(NURL_GPU=cpu "$WH" transcribe "$WORK/model" "$WORK/jfk.wav" 2>/dev/null)
    [ "$GOT_CPU" = "$GOT" ] \
        && ok "CPU backend transcribes identically to CUDA" \
        || { bad "transcription backend parity"; echo "    cpu: [$GOT_CPU]"; }
else
    echo "  SKIP transcription (tokenizer.json or the speech sample did not download)"
fi

echo "== whisper tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
