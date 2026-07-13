# Independent numpy reference for the phi3 forward pass, reading GGUF directly.
# Same job as llama_ref.py / gemma_ref.py. phi3 IS the llama shape (RMSNorm →
# GQA attention with NEOX rotary → SwiGLU), with two twists:
#   * Q, K and V are ONE tensor (attn_qkv, rows q|k|v) and the FFN gate and up
#     are one (ffn_up, rows gate|up) — so the parts are row ranges, not
#     separate weights.
#   * every layer attends only within a sliding window (phi3-mini-4k: 2047).
import sys
import numpy as np
from llama_ref import read_gguf

kvs, tens = read_gguf(sys.argv[1])
ids = [int(x) for x in sys.argv[2].split()]

S = lambda v: v.decode() if isinstance(v, bytes) else v
ARCH = S(kvs['general.architecture'])
K_ = lambda s: kvs[ARCH + '.' + s]
KG = lambda s, d: kvs.get(ARCH + '.' + s, d)

n_embd  = K_('embedding_length')
n_layer = K_('block_count')
n_head  = K_('attention.head_count')
n_kv    = K_('attention.head_count_kv')
n_ff    = K_('feed_forward_length')
eps     = K_('attention.layer_norm_rms_epsilon')
hd      = KG('attention.key_length', n_embd // n_head)
rope_dim = KG('rope.dimension_count', hd)
base     = KG('rope.freq_base', 10000.0)
window   = KG('attention.sliding_window', 0)

f32 = np.float32
qscale = f32(1.0) / np.sqrt(f32(hd))
q_dim = n_head * hd
kv_dim = n_kv * hd


def rms(x, w):
    x = x.astype(f32)
    inv = f32(1.0) / np.sqrt(np.mean(x * x, dtype=f32) + f32(eps))
    return (x * inv * w.astype(f32)).astype(f32)


def rope_neox(v, nh, pos):
    v = v.reshape(nh, hd).copy()
    half = rope_dim // 2
    for j in range(half):
        th = f32(pos) * f32(base) ** f32(-2.0 * j / rope_dim)
        c, s = np.cos(th, dtype=f32), np.sin(th, dtype=f32)
        a, d = v[:, j].copy(), v[:, j + half].copy()
        v[:, j] = a * c - d * s
        v[:, j + half] = a * s + d * c
    return v.reshape(nh * hd)


def silu(x):
    return (x / (f32(1.0) + np.exp(-x))).astype(f32)


T = lambda n: tens[n]
Kc = [np.zeros((0, kv_dim), dtype=f32) for _ in range(n_layer)]
Vc = [np.zeros((0, kv_dim), dtype=f32) for _ in range(n_layer)]


def step(tok, pos):
    x = T('token_embd.weight')[tok].astype(f32)
    for L in range(n_layer):
        xn = rms(x, T('blk.%d.attn_norm.weight' % L))
        # fused qkv: rows q | k | v
        qkv = (T('blk.%d.attn_qkv.weight' % L) @ xn).astype(f32)
        q = qkv[:q_dim]
        k = qkv[q_dim:q_dim + kv_dim]
        v = qkv[q_dim + kv_dim:]
        q = rope_neox(q, n_head, pos)
        k = rope_neox(k, n_kv, pos)
        Kc[L] = np.vstack([Kc[L], k])
        Vc[L] = np.vstack([Vc[L], v])
        lo = max(0, pos - window) if window > 0 else 0
        out = np.zeros(q_dim, dtype=f32)
        for h in range(n_head):
            kh = h // (n_head // n_kv)
            qh = q[h * hd:(h + 1) * hd]
            ks = Kc[L][lo:pos + 1, kh * hd:(kh + 1) * hd]
            sc = (ks @ qh) * qscale
            sc = np.exp(sc - sc.max()); sc /= sc.sum()
            out[h * hd:(h + 1) * hd] = sc @ Vc[L][lo:pos + 1, kh * hd:(kh + 1) * hd]
        x = x + (T('blk.%d.attn_output.weight' % L) @ out).astype(f32)
        xn = rms(x, T('blk.%d.ffn_norm.weight' % L))
        # fused ffn: rows gate | up
        gu = (T('blk.%d.ffn_up.weight' % L) @ xn).astype(f32)
        g, u = gu[:n_ff], gu[n_ff:]
        x = x + (T('blk.%d.ffn_down.weight' % L) @ (silu(g) * u)).astype(f32)
    xn = rms(x, T('output_norm.weight'))
    W = tens.get('output.weight', T('token_embd.weight'))
    return (W @ xn).astype(f32)


logits = None
for pos, tok in enumerate(ids):
    logits = step(tok, pos)

if len(sys.argv) > 3 and sys.argv[3] == 'greedy':
    n = int(sys.argv[4]); out = []
    pos = len(ids)
    for _ in range(n):
        t = int(np.argmax(logits)); out.append(t)
        logits = step(t, pos)
        pos += 1
    print(' '.join(str(t) for t in out))
else:
    for z in logits:
        print(float(z))
