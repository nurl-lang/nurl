# Independent numpy reference for the qwen35 forward pass (Qwen3.5 and
# Qwen3.8: `model_type qwen3_5`), reading the GGUF directly. read_gguf comes
# from llama_ref; the forward below shares no code with the NURL
# implementation it checks, and was itself checked against HF transformers'
# Qwen3_5 model on the original checkpoint (tests/qwen35_hf_check.py).
#
# qwen35 is a hybrid. Three layers of every four are Gated DeltaNet (linear
# attention with a recurrent state), the fourth is full attention:
#
#   linear  qkv = attn_qkv·x  →  causal depthwise conv (kernel 4) + SiLU
#           q, k L2-normalised per head, q scaled by 1/sqrt(dk)
#           beta = sigmoid(ssm_beta·x), g = ssm_a · softplus(ssm_alpha·x + dt_bias)
#           per value head: S ← S·exp(g); S ← S + k ⊗ beta(v − Sᵀk); o = Sᵀq
#           (value head h reads key head h % n_k: the GGUF holds its value
#           heads in ggml's tiled order — llama.cpp's converter moves HF's
#           head h to (h % r)*n_k + h // r, r = n_v/n_k, in every
#           per-value-head tensor; with r = 1 nothing moves)
#           o = RMSNorm(o)·ssm_norm · silu(attn_gate·x) per head; ssm_out·o
#   full    attn_q·x is [q | gate] per head; q, k RMSNormed per head; NEOX
#           rotary on the first rope.dimension_count dims; GQA softmax
#           attention; out · sigmoid(gate); attn_output·out
#
# then post_attention_norm → SwiGLU FFN, residuals around both. The norms are
# stored with the `1 + w` already folded in; ssm_a is stored as −exp(A_log).
# The last nextn_predict_layers blocks are the multi-token-prediction head,
# which plain decoding does not run.
#
# usage: qwen35_ref.py <model.gguf> "<id id id>" [greedy <n>]
import sys
import numpy as np
from llama_ref import read_gguf


def load(path):
    # QWEN35_LAZY=1: dequantise each weight when it is used (a 4B model is
    # 16 GB as f32); only the embedding, read every step, stays.
    import os
    kvs, tens = read_gguf(path, lazy=os.environ.get('QWEN35_LAZY') == '1', keep=('token_embd.weight', 'output.weight'))
    arch = kvs['general.architecture']
    arch = arch.decode() if isinstance(arch, bytes) else arch
    assert arch == 'qwen35', arch
    return kvs, tens


class Qwen35:
    def __init__(self, kvs, tens):
        K = lambda s: kvs['qwen35.' + s]
        KG = lambda s, d: kvs.get('qwen35.' + s, d)
        self.t = tens
        self.n_embd = K('embedding_length')
        self.n_layer = K('block_count') - KG('nextn_predict_layers', 0)
        self.n_head = K('attention.head_count')
        self.n_kv = K('attention.head_count_kv')
        self.eps = np.float32(K('attention.layer_norm_rms_epsilon'))
        self.base = KG('rope.freq_base', 10000.0)
        self.hd = K('attention.key_length')
        self.rope_dim = KG('rope.dimension_count', self.hd)
        self.interval = K('full_attention_interval')
        self.kconv = K('ssm.conv_kernel')
        self.dk = K('ssm.state_size')
        self.nk = K('ssm.group_count')
        self.nv = K('ssm.time_step_rank')
        self.dv = K('ssm.inner_size') // self.nv
        self.W_out = tens.get('output.weight', tens['token_embd.weight'])
        f32 = np.float32
        self.K = [np.zeros((0, self.n_kv * self.hd), f32) for _ in range(self.n_layer)]
        self.V = [np.zeros((0, self.n_kv * self.hd), f32) for _ in range(self.n_layer)]
        cdim = 2 * self.nk * self.dk + self.nv * self.dv
        self.conv = [np.zeros((self.kconv - 1, cdim), f32) for _ in range(self.n_layer)]
        self.S = [np.zeros((self.nv, self.dk, self.dv), f32) for _ in range(self.n_layer)]

    def full(self, L):
        return (L + 1) % self.interval == 0

    def rms(self, x, w):
        x = x.astype(np.float32)
        inv = np.float32(1.0) / np.sqrt(np.mean(x * x, dtype=np.float32) + self.eps)
        return (x * inv * w).astype(np.float32)

    def rope(self, v, nh, pos):
        hd, rd = self.hd, self.rope_dim
        v = v.reshape(nh, hd).copy()
        half = rd // 2
        for j in range(half):
            th = np.float32(pos) * np.float32(self.base) ** np.float32(-2.0 * j / rd)
            c, s = np.cos(th, dtype=np.float32), np.sin(th, dtype=np.float32)
            a, b = v[:, j].copy(), v[:, j + half].copy()
            v[:, j] = a * c - b * s
            v[:, j + half] = a * s + b * c
        return v.reshape(nh * hd)

    def attention(self, L, xn, pos):
        t, hd, nh, nkv = self.t, self.hd, self.n_head, self.n_kv
        qg = (t['blk.%d.attn_q.weight' % L] @ xn).astype(np.float32).reshape(nh, 2 * hd)
        q, gate = qg[:, :hd], qg[:, hd:].reshape(nh * hd)
        k = (t['blk.%d.attn_k.weight' % L] @ xn).astype(np.float32).reshape(nkv, hd)
        v = (t['blk.%d.attn_v.weight' % L] @ xn).astype(np.float32)
        q = np.stack([self.rms(q[h], t['blk.%d.attn_q_norm.weight' % L]) for h in range(nh)]).reshape(-1)
        k = np.stack([self.rms(k[h], t['blk.%d.attn_k_norm.weight' % L]) for h in range(nkv)]).reshape(-1)
        q = self.rope(q, nh, pos)
        k = self.rope(k, nkv, pos)
        self.K[L] = np.vstack([self.K[L], k])
        self.V[L] = np.vstack([self.V[L], v])
        out = np.zeros(nh * hd, np.float32)
        for h in range(nh):
            kh = h // (nh // nkv)
            sc = (self.K[L][:, kh * hd:(kh + 1) * hd] @ q[h * hd:(h + 1) * hd]) / np.sqrt(np.float32(hd))
            sc = np.exp(sc - sc.max())
            sc /= sc.sum()
            out[h * hd:(h + 1) * hd] = sc @ self.V[L][:, kh * hd:(kh + 1) * hd]
        out = out * (1.0 / (1.0 + np.exp(-gate)))
        return (t['blk.%d.attn_output.weight' % L] @ out.astype(np.float32)).astype(np.float32)

    def deltanet(self, L, xn):
        t, nk, nv, dk, dv = self.t, self.nk, self.nv, self.dk, self.dv
        qkv = (t['blk.%d.attn_qkv.weight' % L] @ xn).astype(np.float32)
        # causal depthwise conv over [the last kconv-1 inputs, this one]
        w = t['blk.%d.ssm_conv1d.weight' % L]          # (channels, kconv)
        hist = np.vstack([self.conv[L], qkv[None, :]])  # (kconv, channels)
        self.conv[L] = hist[1:]
        c = (hist.T * w).sum(axis=1).astype(np.float32)
        with np.errstate(over='ignore'):
            c = (c / (1.0 + np.exp(-c))).astype(np.float32)
        q = c[:nk * dk].reshape(nk, dk)
        k = c[nk * dk:2 * nk * dk].reshape(nk, dk)
        v = c[2 * nk * dk:].reshape(nv, dv)
        l2 = lambda a: a / np.sqrt((a * a).sum(-1, keepdims=True) + np.float32(1e-6))
        q = l2(q) / np.sqrt(np.float32(dk))
        k = l2(k)
        b = (t['blk.%d.ssm_beta.weight' % L] @ xn).astype(np.float32)
        a = (t['blk.%d.ssm_alpha.weight' % L] @ xn).astype(np.float32)
        beta = 1.0 / (1.0 + np.exp(-b))
        sp = a + t['blk.%d.ssm_dt.bias' % L]
        sp = np.where(sp > 20, sp, np.log1p(np.exp(np.minimum(sp, 20))))
        g = t['blk.%d.ssm_a' % L] * sp
        z = (t['blk.%d.attn_gate.weight' % L] @ xn).astype(np.float32).reshape(nv, dv)
        o = np.zeros((nv, dv), np.float32)
        S = self.S[L]
        for h in range(nv):
            kh = h % nk
            S[h] *= np.float32(np.exp(g[h]))
            kv = S[h].T @ k[kh]
            S[h] += np.outer(k[kh], (v[h] - kv) * beta[h]).astype(np.float32)
            o[h] = S[h].T @ q[kh]
        nw = t['blk.%d.ssm_norm.weight' % L]
        with np.errstate(over='ignore'):
            o = np.stack([self.rms(o[h], nw) * (z[h] / (1.0 + np.exp(-z[h]))) for h in range(nv)])
        return (t['blk.%d.ssm_out.weight' % L] @ o.reshape(-1).astype(np.float32)).astype(np.float32)

    def step(self, tok, pos):
        t = self.t
        x = t['token_embd.weight'][tok].astype(np.float32)
        for L in range(self.n_layer):
            xn = self.rms(x, t['blk.%d.attn_norm.weight' % L])
            x = x + (self.attention(L, xn, pos) if self.full(L) else self.deltanet(L, xn))
            xn = self.rms(x, t['blk.%d.post_attention_norm.weight' % L])
            g = (t['blk.%d.ffn_gate.weight' % L] @ xn).astype(np.float32)
            u = (t['blk.%d.ffn_up.weight' % L] @ xn).astype(np.float32)
            with np.errstate(over='ignore'):
                g = (g / (1.0 + np.exp(-g)) * u).astype(np.float32)
            x = x + (t['blk.%d.ffn_down.weight' % L] @ g).astype(np.float32)
        return (self.W_out @ self.rms(x, t['output_norm.weight'])).astype(np.float32)


if __name__ == '__main__':
    kvs, tens = load(sys.argv[1])
    m = Qwen35(kvs, tens)
    ids = [int(x) for x in sys.argv[2].split()]
    logits = None
    for pos, tok in enumerate(ids):
        logits = m.step(tok, pos)
    if len(sys.argv) > 3 and sys.argv[3] == 'greedy':
        n = int(sys.argv[4])
        pos = len(ids)
        out = []
        for _ in range(n):
            tk = int(np.argmax(logits))
            out.append(tk)
            logits = m.step(tk, pos)
            pos += 1
        print(' '.join(map(str, out)))
    else:
        for v in logits:
            print('%.6f' % v)
