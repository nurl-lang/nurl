# Independent numpy reference for the gemma3 forward pass, reading GGUF
# directly. Same job as llama_ref.py, different architecture: scaled
# embeddings, (1 + w) RMSNorm weights, per-head Q/K norms, post-attention and
# post-FFW norms, GeGLU, and sliding-window attention on five of every six
# layers (those layers also use their own, smaller RoPE base). gemma's `1 + w`
# norm weights are NOT applied here: the GGUF converter has already folded the
# +1 into the stored tensors.
import sys
import numpy as np
from llama_ref import read_gguf          # the GGUF reader + dequant, reused

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
eps     = K_('attention.layer_norm_rms_epsilon')
hd      = KG('attention.key_length', n_embd // n_head)
rope_dim = KG('rope.dimension_count', hd)
base     = KG('rope.freq_base', 10000.0)
base_swa = KG('rope.local.freq_base', 10000.0)
window   = KG('attention.sliding_window', 0)
qpre     = KG('attention.query_pre_attn_scalar', hd)
PERIOD   = 6                              # every 6th layer is full-attention

f32 = np.float32
qscale = f32(1.0) / np.sqrt(f32(qpre))
embd_scale = np.sqrt(f32(n_embd))


def rms(x, w):
    # gemma's `1 + w` is already folded into the GGUF's norm weights by the
    # converter, so this is the plain form (see model.nu).
    x = x.astype(f32)
    inv = f32(1.0) / np.sqrt(np.mean(x * x, dtype=f32) + f32(eps))
    return (x * inv * w.astype(f32)).astype(f32)


def rms_heads(v, nh, w):                  # per-head RMSNorm over head_dim
    v = v.reshape(nh, hd)
    return np.stack([rms(v[h], w) for h in range(nh)]).reshape(nh * hd)


def rope_neox(v, nh, pos, b):
    v = v.reshape(nh, hd).copy()
    half = rope_dim // 2
    for j in range(half):
        th = f32(pos) * f32(b) ** f32(-2.0 * j / rope_dim)
        c, s = np.cos(th, dtype=f32), np.sin(th, dtype=f32)
        a, d = v[:, j].copy(), v[:, j + half].copy()
        v[:, j] = a * c - d * s
        v[:, j + half] = a * s + d * c
    return v.reshape(nh * hd)


def gelu(x):
    c = f32(0.7978845608028654) * (x + f32(0.044715) * x ** 3)
    return (f32(0.5) * x * (f32(1.0) + np.tanh(c))).astype(f32)


T = lambda n: tens[n]
Kc = [np.zeros((0, n_kv * hd), dtype=f32) for _ in range(n_layer)]
Vc = [np.zeros((0, n_kv * hd), dtype=f32) for _ in range(n_layer)]


HID = []            # per-layer hidden state of the last stepped position

def step(tok, pos):
    global logits
    x = T('token_embd.weight')[tok].astype(f32) * embd_scale
    HID.clear(); HID.append(x.copy())
    for L in range(n_layer):
        full  = (L + 1) % PERIOD == 0
        b_L   = base if full else base_swa
        win   = 0 if full else window
        xn = rms(x, T('blk.%d.attn_norm.weight' % L))
        q = (T('blk.%d.attn_q.weight' % L) @ xn).astype(f32)
        k = (T('blk.%d.attn_k.weight' % L) @ xn).astype(f32)
        v = (T('blk.%d.attn_v.weight' % L) @ xn).astype(f32)
        q = rms_heads(q, n_head, T('blk.%d.attn_q_norm.weight' % L))
        k = rms_heads(k, n_kv,   T('blk.%d.attn_k_norm.weight' % L))
        q = rope_neox(q, n_head, pos, b_L)
        k = rope_neox(k, n_kv,   pos, b_L)
        Kc[L] = np.vstack([Kc[L], k])
        Vc[L] = np.vstack([Vc[L], v])
        lo = max(0, pos - win) if win > 0 else 0
        out = np.zeros(n_head * hd, dtype=f32)
        for h in range(n_head):
            kh = h // (n_head // n_kv)
            qh = q[h * hd:(h + 1) * hd]
            ks = Kc[L][lo:pos + 1, kh * hd:(kh + 1) * hd]
            sc = (ks @ qh) * qscale
            sc = np.exp(sc - sc.max()); sc /= sc.sum()
            out[h * hd:(h + 1) * hd] = sc @ Vc[L][lo:pos + 1, kh * hd:(kh + 1) * hd]
        a = (T('blk.%d.attn_output.weight' % L) @ out).astype(f32)
        a = rms(a, T('blk.%d.post_attention_norm.weight' % L))
        x = x + a
        xn = rms(x, T('blk.%d.ffn_norm.weight' % L))
        g = (T('blk.%d.ffn_gate.weight' % L) @ xn).astype(f32)
        u = (T('blk.%d.ffn_up.weight' % L) @ xn).astype(f32)
        ff = (T('blk.%d.ffn_down.weight' % L) @ (gelu(g) * u)).astype(f32)
        ff = rms(ff, T('blk.%d.post_ffw_norm.weight' % L))
        x = x + ff
        HID.append(x.copy())
    xn = rms(x, T('output_norm.weight'))
    W = tens.get('output.weight', T('token_embd.weight'))
    return (W @ xn).astype(f32)


logits = None
for pos, tok in enumerate(ids):
    logits = step(tok, pos)

if len(sys.argv) > 3 and sys.argv[3] == 'quiet':
    pass
elif len(sys.argv) > 3 and sys.argv[3] == 'greedy':
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
