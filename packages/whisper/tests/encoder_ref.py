# Independent numpy reference for whisper's ENCODER, reading the safetensors
# checkpoint directly.
#
# It is itself checked against HF's WhisperModel.encoder (r = 1.00000000,
# max|delta| = 4.3e-4 in float64) — so when the GPU path disagrees with THIS, the
# GPU path is what is wrong. That is exactly how the positional-embedding bug was
# found: the reference agreed with HF, and the kernels did not agree with either.
import sys
import json
import struct
import numpy as np


def load(path):
    raw = open(path, 'rb').read()
    n = struct.unpack('<Q', raw[:8])[0]
    hdr = json.loads(raw[8:8 + n])

    def T(name):
        e = hdr[name]
        a, b = e['data_offsets']
        return np.frombuffer(raw[8 + n + a:8 + n + b], dtype='<f4').reshape(e['shape']).astype(np.float64)
    return T


def gelu(x):
    # The ERROR-FUNCTION gelu, which is what whisper was trained with — not the
    # tanh approximation (which gemma wants, and which is a different function).
    from math import sqrt, erf
    return 0.5 * x * (1 + np.vectorize(erf)(x / sqrt(2)))


def ln(x, w, b, eps=1e-5):
    m = x.mean(-1, keepdims=True)
    v = x.var(-1, keepdims=True)
    return (x - m) / np.sqrt(v + eps) * w + b


def conv1d(x, W, b, stride):          # x (C_in, T), W (C_out, C_in, 3)
    T = x.shape[1]
    xp = np.pad(x, ((0, 0), (1, 1)))
    T_out = (T + 2 - 3) // stride + 1
    y = np.zeros((W.shape[0], T_out))
    for t in range(T_out):
        y[:, t] = np.einsum('oik,ik->o', W, xp[:, t * stride:t * stride + 3]) + b
    return y


def encode(T, mel, n_layer, n_head):  # mel (n_mels, 3000)
    h = gelu(conv1d(mel, T('model.encoder.conv1.weight'), T('model.encoder.conv1.bias'), 1))
    h = gelu(conv1d(h,   T('model.encoder.conv2.weight'), T('model.encoder.conv2.bias'), 2))
    # embed_positions is a MATRIX — one vector per position, not a row broadcast
    x = h.T + T('model.encoder.embed_positions.weight')
    d_model = x.shape[1]
    hd = d_model // n_head
    for L in range(n_layer):
        p = f'model.encoder.layers.{L}.'
        r = x
        y = ln(x, T(p + 'self_attn_layer_norm.weight'), T(p + 'self_attn_layer_norm.bias'))
        q = y @ T(p + 'self_attn.q_proj.weight').T + T(p + 'self_attn.q_proj.bias')
        k = y @ T(p + 'self_attn.k_proj.weight').T          # k_proj has NO bias
        v = y @ T(p + 'self_attn.v_proj.weight').T + T(p + 'self_attn.v_proj.bias')
        q = q.reshape(-1, n_head, hd).transpose(1, 0, 2)
        k = k.reshape(-1, n_head, hd).transpose(1, 0, 2)
        v = v.reshape(-1, n_head, hd).transpose(1, 0, 2)
        sc = q @ k.transpose(0, 2, 1) / np.sqrt(hd)         # NON-causal: no mask
        sc = np.exp(sc - sc.max(-1, keepdims=True))
        sc /= sc.sum(-1, keepdims=True)
        o = (sc @ v).transpose(1, 0, 2).reshape(-1, d_model)
        x = r + (o @ T(p + 'self_attn.out_proj.weight').T + T(p + 'self_attn.out_proj.bias'))
        r = x
        y = ln(x, T(p + 'final_layer_norm.weight'), T(p + 'final_layer_norm.bias'))
        y = gelu(y @ T(p + 'fc1.weight').T + T(p + 'fc1.bias'))
        x = r + (y @ T(p + 'fc2.weight').T + T(p + 'fc2.bias'))
    return ln(x, T('model.encoder.layer_norm.weight'), T('model.encoder.layer_norm.bias'))


if __name__ == "__main__":
    # encoder_ref.py <model.safetensors> <mel.f32 (frames x n_mels)> <out.f32> [n_layer] [n_head] [n_mels]
    T = load(sys.argv[1])
    n_layer = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    n_head = int(sys.argv[5]) if len(sys.argv) > 5 else 6
    n_mels = int(sys.argv[6]) if len(sys.argv) > 6 else 80
    mel = np.fromfile(sys.argv[2], dtype='<f4').reshape(-1, n_mels).T.astype(np.float64)
    encode(T, mel, n_layer, n_head).astype('<f4').tofile(sys.argv[3])
