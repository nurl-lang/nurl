# Independent numpy reference for whisper's log-mel spectrogram, written from
# the specification (transformers' audio_utils.py + feature_extraction_whisper.py)
# rather than from our implementation.
#
# It is a REGRESSION guard, not the oracle: a reference written by the same hand
# as the code can share the code's misconceptions. The oracle is Hugging Face's
# own WhisperFeatureExtractor, which audio_test.sh compares against whenever
# transformers is importable — and which this reference was checked against.
import sys
import numpy as np


def hz_to_mel_slaney(f):
    f = np.asarray(f, dtype=np.float64)
    mels = 3.0 * f / 200.0
    log_region = f >= 1000.0
    mels = np.where(log_region, 15.0 + np.log(np.maximum(f, 1e-9) / 1000.0) * (27.0 / np.log(6.4)), mels)
    return mels


def mel_to_hz_slaney(m):
    m = np.asarray(m, dtype=np.float64)
    freqs = 200.0 * m / 3.0
    log_region = m >= 15.0
    freqs = np.where(log_region, 1000.0 * np.exp((np.log(6.4) / 27.0) * (m - 15.0)), freqs)
    return freqs


def mel_filters(n_fft=400, n_mels=80, rate=16000, f_min=0.0, f_max=8000.0):
    n_bins = n_fft // 2 + 1
    fft_hz = np.linspace(0.0, rate // 2, n_bins)
    edges_mel = np.linspace(hz_to_mel_slaney(f_min), hz_to_mel_slaney(f_max), n_mels + 2)
    edges = mel_to_hz_slaney(edges_mel)
    diff = np.diff(edges)
    slopes = edges[None, :] - fft_hz[:, None]
    down = -slopes[:, :-2] / diff[:-1]
    up = slopes[:, 2:] / diff[1:]
    fb = np.maximum(0.0, np.minimum(down, up))
    enorm = 2.0 / (edges[2:n_mels + 2] - edges[:n_mels])
    return fb * enorm[None, :]                      # (n_bins, n_mels)


def log_mel(x, n_fft=400, hop=160, n_mels=80, rate=16000):
    # periodic Hann: hanning(N+1)[:-1]
    win = np.hanning(n_fft + 1)[:-1]
    x = np.pad(np.asarray(x, dtype=np.float64), (n_fft // 2, n_fft // 2), mode="reflect")
    frames = 1 + (len(x) - n_fft) // hop
    spec = np.empty((frames, n_fft // 2 + 1))
    for i in range(frames):
        seg = x[i * hop: i * hop + n_fft] * win
        spec[i] = np.abs(np.fft.rfft(seg)) ** 2
    spec = spec[:-1]                                # whisper drops the last frame
    mel = spec @ mel_filters(n_fft, n_mels, rate)   # (frames, n_mels)
    log_spec = np.log10(np.maximum(mel, 1e-10))
    log_spec = np.maximum(log_spec, log_spec.max() - 8.0)
    return (log_spec + 4.0) / 4.0


if __name__ == "__main__":
    import wave
    w = wave.open(sys.argv[1], "rb")
    pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 480000
    if len(pcm) < n:
        pcm = np.pad(pcm, (0, n - len(pcm)))
    else:
        pcm = pcm[:n]
    log_mel(pcm).astype("<f4").tofile(sys.argv[3])
