# Independent numpy reference for the qwen3 forward pass, reading the GGUF
# directly (read_gguf comes from llama_ref; the forward below shares no code
# with the NURL implementation it is used to check).
#
# qwen3 is the llama shape with four differences:
#   · NEOX rotary (the two halves of the span rotate, not adjacent lanes)
#   · no Q/K/V bias
#   · head_dim is STATED (attention.key_length); n_head*head_dim need not
#     equal n_embd — Qwen3-0.6B is 16*128 = 2048 against an n_embd of 1024
#   · every head's Q and K vector is RMSNormed before the rotation, with a
#     per-layer weight of head_dim elements
#
# usage: qwen3_ref.py <model.gguf> "<id id id>" [greedy <n>]
import sys
import numpy as np
from llama_ref import read_gguf

if __name__ == '__main__':
    kvs, tens = read_gguf(sys.argv[1])
    ids = [int(x) for x in sys.argv[2].split()]
    arch = kvs['general.architecture']
    arch = arch.decode() if isinstance(arch, bytes) else arch
    assert arch == 'qwen3', arch
    K_ = lambda s: kvs['qwen3.' + s]
    KG = lambda s, d: kvs.get('qwen3.' + s, d)

    n_embd = K_('embedding_length')
    n_layer = K_('block_count')
    n_head = K_('attention.head_count')
    n_kv = K_('attention.head_count_kv')
    eps = K_('attention.layer_norm_rms_epsilon')
    base = KG('rope.freq_base', 10000.0)
    hd = KG('attention.key_length', n_embd // n_head)
    rope_dim = KG('rope.dimension_count', hd)
    q_dim = n_head * hd

    f32 = np.float32

    def rms(x, w):
        x = x.astype(f32)
        inv = f32(1.0) / np.sqrt(np.mean(x * x, dtype=f32) + f32(eps))
        return (x * inv * w).astype(f32)

    def head_rms(v, nh, w):
        """RMSNorm each of the nh head vectors of `v` (length nh*hd)."""
        v = v.reshape(nh, hd)
        return np.stack([rms(v[h], w) for h in range(nh)]).reshape(nh * hd)

    def rope(v, nh, pos):
        v = v.reshape(nh, hd).copy()
        half = rope_dim // 2
        for j in range(half):
            th = f32(pos) * f32(base) ** f32(-2.0 * j / rope_dim)
            c, s = np.cos(th, dtype=f32), np.sin(th, dtype=f32)
            i0, i1 = j, j + half          # NEOX
            a, b = v[:, i0].copy(), v[:, i1].copy()
            v[:, i0] = a * c - b * s
            v[:, i1] = a * s + b * c
        return v.reshape(nh * hd)

    Kc = [np.zeros((0, n_kv * hd), dtype=f32) for _ in range(n_layer)]
    Vc = [np.zeros((0, n_kv * hd), dtype=f32) for _ in range(n_layer)]
    W_out = tens.get('output.weight', tens['token_embd.weight'])

    def step(tok, pos):
        x = tens['token_embd.weight'][tok].astype(f32)
        for L in range(n_layer):
            xn = rms(x, tens['blk.%d.attn_norm.weight' % L])
            q = (tens['blk.%d.attn_q.weight' % L] @ xn).astype(f32)
            k = (tens['blk.%d.attn_k.weight' % L] @ xn).astype(f32)
            v = (tens['blk.%d.attn_v.weight' % L] @ xn).astype(f32)
            q = head_rms(q, n_head, tens['blk.%d.attn_q_norm.weight' % L])
            k = head_rms(k, n_kv, tens['blk.%d.attn_k_norm.weight' % L])
            q = rope(q, n_head, pos)
            k = rope(k, n_kv, pos)
            Kc[L] = np.vstack([Kc[L], k])
            Vc[L] = np.vstack([Vc[L], v])
            out = np.zeros(q_dim, dtype=f32)
            for h in range(n_head):
                kh = h // (n_head // n_kv)
                qh = q[h * hd:(h + 1) * hd]
                ks = Kc[L][:, kh * hd:(kh + 1) * hd]
                sc = (ks @ qh) / np.sqrt(f32(hd))
                sc = np.exp(sc - sc.max())
                sc /= sc.sum()
                out[h * hd:(h + 1) * hd] = sc @ Vc[L][:, kh * hd:(kh + 1) * hd]
            x = x + (tens['blk.%d.attn_output.weight' % L] @ out).astype(f32)
            xn = rms(x, tens['blk.%d.ffn_norm.weight' % L])
            g = (tens['blk.%d.ffn_gate.weight' % L] @ xn).astype(f32)
            u = (tens['blk.%d.ffn_up.weight' % L] @ xn).astype(f32)
            # exp(-g) overflows to inf for very negative g; g/inf is -0.0,
            # which is silu's limit there — the warning is noise, not a bug.
            with np.errstate(over='ignore'):
                g = (g / (1.0 + np.exp(-g)) * u).astype(f32)
            x = x + (tens['blk.%d.ffn_down.weight' % L] @ g).astype(f32)
        return (W_out @ rms(x, tens['output_norm.weight'])).astype(f32)

    logits = None
    for pos, tok in enumerate(ids):
        logits = step(tok, pos)

    if len(sys.argv) > 3 and sys.argv[3] == 'greedy':
        n = int(sys.argv[4])
        pos = len(ids)
        out = []
        for _ in range(n):
            t = int(np.argmax(logits))
            out.append(t)
            logits = step(t, pos)
            pos += 1
        print(' '.join(map(str, out)))
    else:
        for v in logits:
            print('%.6f' % v)
