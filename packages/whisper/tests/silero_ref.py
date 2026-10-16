#!/usr/bin/env python3
# tests/silero_ref.py — Silero VAD v5 (16 kHz) in numpy, from the safetensors file.
#
#   python3 tests/silero_ref.py vad/silero_vad_v5.safetensors audio.wav probs.txt
#
# An independent reading of the same network src/silero.nu runs: numpy's
# tensordot convolutions instead of loops, PyTorch's LSTM cell written out.
# It was checked against onnxruntime on snakers4/silero-vad's ONNX file
# (max |dp| 1.8e-6), so agreeing with it is agreeing with the original.
# Compares p(speech) per 32 ms chunk against probs.txt ("t p" lines) and
# exits 1 past 1e-4. Needs: numpy.
import json, struct, sys, wave
import numpy as np

def load(path):
    b = open(path, "rb").read()
    n = struct.unpack("<Q", b[:8])[0]
    hdr = json.loads(b[8:8 + n]); base = 8 + n; W = {}
    for k, v in hdr.items():
        if k == "__metadata__": continue
        a, z = v["data_offsets"]
        W[k] = np.frombuffer(b[base + a: base + z], dtype="<f4").reshape(v["shape"]).astype(np.float64)
    return W

def conv(x, w, b, stride):
    cin, T = x.shape; cout, _, k = w.shape
    xp = np.pad(x, ((0, 0), (1, 1))); To = (T + 2 - k) // stride + 1
    out = np.stack([np.tensordot(w, xp[:, t * stride: t * stride + k], axes=([1, 2], [0, 1])) for t in range(To)], 1)
    return np.maximum(out + b[:, None], 0)

def main():
    W = load(sys.argv[1])
    w = wave.open(sys.argv[2]); assert w.getframerate() == 16000 and w.getnchannels() == 1
    x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768
    n = np.arange(256); win = 0.5 - 0.5 * np.cos(2 * np.pi * n / 256)
    k = np.arange(129)[:, None]
    re_b = win * np.cos(2 * np.pi * k * n / 256); im_b = -win * np.sin(2 * np.pi * k * n / 256)
    sig = lambda v: 1 / (1 + np.exp(-v))
    h = np.zeros(128); c = np.zeros(128); ctx = np.zeros(64); ref = []
    for off in range(0, len(x) - 511, 512):
        f = np.concatenate([ctx, x[off:off + 512]]); ctx = f[-64:]
        fp = np.concatenate([f, f[-2:-66:-1]])
        fr = np.stack([fp[t * 128: t * 128 + 256] for t in range(4)], 1)
        mag = np.sqrt((re_b @ fr) ** 2 + (im_b @ fr) ** 2)
        e = conv(mag, W["encoder.0.reparam_conv.weight"], W["encoder.0.reparam_conv.bias"], 1)
        e = conv(e, W["encoder.1.reparam_conv.weight"], W["encoder.1.reparam_conv.bias"], 2)
        e = conv(e, W["encoder.2.reparam_conv.weight"], W["encoder.2.reparam_conv.bias"], 2)
        e = conv(e, W["encoder.3.reparam_conv.weight"], W["encoder.3.reparam_conv.bias"], 1)[:, 0]
        g = W["decoder.rnn.weight_ih"] @ e + W["decoder.rnn.bias_ih"] + W["decoder.rnn.weight_hh"] @ h + W["decoder.rnn.bias_hh"]
        c = sig(g[128:256]) * c + sig(g[:128]) * np.tanh(g[256:384]); h = sig(g[384:]) * np.tanh(c)
        ref.append(sig(W["decoder.decoder.2.weight"][0, :, 0] @ np.maximum(h, 0) + W["decoder.decoder.2.bias"][0]))
    ours = [float(l.split()[1]) for l in open(sys.argv[3]) if l.strip()]
    assert len(ours) == len(ref), f"{len(ours)} chunks vs {len(ref)}"
    d = np.abs(np.array(ours) - np.array(ref)).max()
    print(f"{len(ref)} chunks, max |dp| {d:.2e}, speech in {sum(p > 0.5 for p in ref)}")
    sys.exit(0 if d < 1e-4 else 1)

main()
