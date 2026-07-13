#!/bin/sh
# ============================================================
#  packages/audio — test suite
#
#  1. WAV: round-trip, every bit depth, and files that lie about their chunks
#  2. resample: the thing linear interpolation gets WRONG — a tone above the
#     new Nyquist frequency must be filtered out, not folded back into the band
#  3. mel: against an independent numpy reference, and — when transformers is
#     importable — against Hugging Face's own WhisperFeatureExtractor, which is
#     the actual oracle
#
#  Run from the package dir:  ./tests/audio_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t audio.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/4] build"
if ! $NURL src/main.nu "$WORK/audio" >/dev/null 2>"$WORK/build.err"; then
    echo "  build FAILED"; cat "$WORK/build.err"; exit 1
fi
A="$WORK/audio"

echo "[2/4] WAV — round-trip, bit depths, and files that lie"
"$A" tone "$WORK/tone.wav" --rate 16000 --seconds 1 >/dev/null 2>&1
"$A" info "$WORK/tone.wav" | grep -q "16000 Hz, 1 ch, 16 bit, 16000 frames" \
    && ok "write → read round-trip (16 kHz mono 16-bit, 1 s)" \
    || { bad "round-trip"; "$A" info "$WORK/tone.wav"; }

python3 - "$WORK" <<'PYEOF'
# every bit depth and format a WAV can hold, plus files that lie about it
import sys, struct, os
W = sys.argv[1]

def riff(fmt, bits, ch, rate, data):
    block = ch * (bits // 8)
    hdr = b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVE'
    hdr += b'fmt ' + struct.pack('<IHHIIHH', 16, fmt, ch, rate, rate * block, block, bits)
    hdr += b'data' + struct.pack('<I', len(data))
    return hdr + data

# 8-bit unsigned: 128 is silence
open(W + '/d8.wav', 'wb').write(riff(1, 8, 1, 8000, bytes([128, 255, 0, 128])))
# 24-bit signed
open(W + '/d24.wav', 'wb').write(riff(1, 24, 1, 16000, b'\x00\x00\x40' + b'\x00\x00\xc0'))
# 32-bit float
open(W + '/f32.wav', 'wb').write(riff(3, 32, 1, 16000, struct.pack('<ff', 0.5, -0.5)))

# now the lies
open(W + '/lie_size.wav', 'wb').write(
    b'RIFF' + struct.pack('<I', 36) + b'WAVE'
    + b'fmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 16000, 32000, 2, 16)
    + b'data' + struct.pack('<I', 0x7fffffff) + b'\x00\x00')   # data claims 2 GB
open(W + '/lie_rate.wav', 'wb').write(riff(1, 16, 1, 0, b'\x00\x00'))       # 0 Hz
open(W + '/lie_ch.wav', 'wb').write(riff(1, 16, 0, 16000, b'\x00\x00'))     # 0 channels
open(W + '/lie_bits.wav', 'wb').write(riff(1, 12, 1, 16000, b'\x00\x00'))   # 12-bit
open(W + '/truncated.wav', 'wb').write(riff(1, 16, 1, 16000, b'\x00' * 100)[:30])
open(W + '/notriff.wav', 'wb').write(b'This is not a wav file at all, sorry.')
PYEOF

"$A" info "$WORK/d8.wav"  | grep -q "8 bit"  && ok "8-bit unsigned PCM"  || bad "8-bit"
"$A" info "$WORK/d24.wav" | grep -q "24 bit" && ok "24-bit signed PCM"   || bad "24-bit"
"$A" info "$WORK/f32.wav" | grep -q "32 bit" && ok "32-bit IEEE float"   || bad "float32"

LIES=0
for f in lie_size lie_rate lie_ch lie_bits truncated notriff; do
    if "$A" info "$WORK/$f.wav" >/dev/null 2>&1; then
        bad "a lying file was accepted: $f"
        LIES=1
    fi
done
[ "$LIES" = "0" ] && ok "6 malformed files (2 GB data chunk, 0 Hz, 0 channels, 12-bit, truncated, not RIFF) are clean errors"

echo "[3/4] resample — the thing linear interpolation gets wrong"
python3 - "$WORK" <<'PYEOF'
import sys, numpy as np, wave, struct
W = sys.argv[1]; sr = 44100
t = np.arange(2 * sr) / sr
x = 0.4*np.sin(2*np.pi*220*t) + 0.25*np.sin(2*np.pi*3000*t) + 0.3*np.sin(2*np.pi*12000*t)
x = x / np.abs(x).max() * 0.9
w = wave.open(W + '/in44k.wav', 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(b''.join(struct.pack('<h', int(v * 32767)) for v in x)); w.close()
PYEOF
"$A" resample "$WORK/in44k.wav" "$WORK/out16k.wav" --rate 16000 >/dev/null 2>&1
python3 - "$WORK" <<'PYEOF' && ok "12 kHz tone (above the new Nyquist) is filtered out, not folded back to 4 kHz" || bad "resampler aliases"
import sys, numpy as np, wave
W = sys.argv[1]
w = wave.open(W + '/out16k.wav', 'rb')
y = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float) / 32768.0
sp = np.abs(np.fft.rfft(y * np.hanning(len(y))))
fr = np.fft.rfftfreq(len(y), 1 / 16000)
def lvl(f):
    i = np.argmin(abs(fr - f))
    return 20 * np.log10(max(sp[max(0, i-3):i+4].max(), 1e-12) / sp.max())
# the signal below Nyquist survives …
assert lvl(220) > -3, f"220 Hz lost: {lvl(220):.1f} dB"
assert lvl(3000) > -12, f"3 kHz lost: {lvl(3000):.1f} dB"
# … and the 12 kHz tone does NOT reappear at |16000-12000| = 4 kHz
assert lvl(4000) < -60, f"12 kHz aliased into 4 kHz at {lvl(4000):.1f} dB (linear interpolation would)"
PYEOF

echo "[4/4] mel — against numpy, and against Hugging Face when it is installed"
python3 - "$WORK" <<'PYEOF'
import sys, numpy as np, wave, struct
W = sys.argv[1]; sr = 16000
t = np.arange(3 * sr) / sr
rng = np.random.RandomState(7)
x = 0.4*np.sin(2*np.pi*220*t)*(1 + 0.5*np.sin(2*np.pi*3*t))
x += 0.25*np.sin(2*np.pi*880*t + 2*np.sin(2*np.pi*5*t))
x += 0.15*np.sin(2*np.pi*2400*t) + 0.05*rng.randn(t.size)
x = x / np.abs(x).max() * 0.9
w = wave.open(W + '/speechy.wav', 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(b''.join(struct.pack('<h', int(v * 32767)) for v in x)); w.close()
PYEOF
"$A" mel "$WORK/speechy.wav" -o "$WORK/mel_ours.f32" >/dev/null 2>&1
python3 tests/mel_ref.py "$WORK/speechy.wav" 480000 "$WORK/mel_ref.f32"
python3 - "$WORK" <<'PYEOF' && ok "log-mel == independent numpy reference (80 x 3000)" || bad "mel vs numpy"
import sys, numpy as np
W = sys.argv[1]
ours = np.fromfile(W + '/mel_ours.f32', dtype='<f4').reshape(3000, 80)
ref  = np.fromfile(W + '/mel_ref.f32',  dtype='<f4').reshape(3000, 80)
d = np.abs(ours - ref).max()
assert ours.shape == ref.shape
assert d < 1e-4, f"max|delta| = {d:.3e}"
PYEOF

# the real oracle, when it is available
python3 - "$WORK" 2>/dev/null <<'PYEOF' && ok "log-mel == Hugging Face WhisperFeatureExtractor" || echo "  SKIP HF oracle (transformers not importable)"
import sys, numpy as np, wave
W = sys.argv[1]
from transformers import WhisperFeatureExtractor
w = wave.open(W + '/speechy.wav', 'rb')
x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float64) / 32768.0
fe = WhisperFeatureExtractor.from_pretrained('openai/whisper-tiny')
hf = fe(x, sampling_rate=16000, return_tensors="np")["input_features"][0]     # (80, 3000)
ours = np.fromfile(W + '/mel_ours.f32', dtype='<f4').reshape(3000, 80).T
d = np.abs(ours - hf).max()
assert d < 1e-3, f"max|delta| vs HF = {d:.3e}"
PYEOF

echo "== audio tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
