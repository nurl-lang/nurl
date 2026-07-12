# Vectorised ggml dequantisation (numpy) — same layouts as the scalar
# reference in packages/gguf/tests/kquant_ref.py, fast enough to run a
# whole 0.5B forward pass.
import numpy as np

def _f16(b):  # (n,2) uint8 → float32
    return b.view(np.uint8).reshape(-1, 2).copy().view('<f2').astype(np.float32).ravel()

def deq_q8_0(raw, n):
    b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 34)
    d = _f16(b[:, 0:2])[:, None]
    q = b[:, 2:34].view(np.int8).astype(np.float32)
    return (d * q).ravel()[:n]

def deq_q5_0(raw, n):
    b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 22)
    d = _f16(b[:, 0:2])[:, None]
    qh = b[:, 2:6].copy().view('<u4').ravel()[:, None]
    qs = b[:, 6:22]
    j = np.arange(16)
    lo = (qs & 0xF) | (((qh >> j) & 1) << 4).astype(np.uint8)
    hi = (qs >> 4) | (((qh >> (j + 16)) & 1) << 4).astype(np.uint8)
    out = np.empty((b.shape[0], 32), dtype=np.float32)
    out[:, :16] = d * (lo.astype(np.float32) - 16)
    out[:, 16:] = d * (hi.astype(np.float32) - 16)
    return out.ravel()[:n]

def _k4_scales(sc):           # sc: (nb,12) uint8 → (nb,8) scale, (nb,8) min
    s = np.empty((sc.shape[0], 8), dtype=np.float32)
    m = np.empty((sc.shape[0], 8), dtype=np.float32)
    for j in range(8):
        if j < 4:
            s[:, j] = sc[:, j] & 63
            m[:, j] = sc[:, j + 4] & 63
        else:
            s[:, j] = (sc[:, j + 4] & 0xF) | ((sc[:, j - 4] >> 6) << 4)
            m[:, j] = (sc[:, j + 4] >> 4) | ((sc[:, j] >> 6) << 4)
    return s, m

def deq_q4_k(raw, n):
    b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 144)
    d = _f16(b[:, 0:2])[:, None]
    dmin = _f16(b[:, 2:4])[:, None]
    s, m = _k4_scales(b[:, 4:16])
    qs = b[:, 16:144].reshape(-1, 4, 32)          # 4 groups of 32 bytes
    lo = (qs & 0xF).astype(np.float32)            # sub-blocks 0,2,4,6
    hi = (qs >> 4).astype(np.float32)             # sub-blocks 1,3,5,7
    out = np.empty((b.shape[0], 8, 32), dtype=np.float32)
    for sub in range(8):
        q = lo[:, sub // 2] if sub % 2 == 0 else hi[:, sub // 2]
        out[:, sub] = (d * s[:, sub:sub+1]) * q - (dmin * m[:, sub:sub+1])
    return out.reshape(b.shape[0], 256).ravel()[:n]

def deq_q5_k(raw, n):
    b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 176)
    d = _f16(b[:, 0:2])[:, None]
    dmin = _f16(b[:, 2:4])[:, None]
    s, m = _k4_scales(b[:, 4:16])
    qh = b[:, 16:48]
    qs = b[:, 48:176].reshape(-1, 4, 32)
    out = np.empty((b.shape[0], 8, 32), dtype=np.float32)
    for sub in range(8):
        base = qs[:, sub // 2]
        q = (base & 0xF) if sub % 2 == 0 else (base >> 4)
        hbit = ((qh >> sub) & 1).astype(np.float32)
        out[:, sub] = (d * s[:, sub:sub+1]) * (q.astype(np.float32) + hbit * 16) - (dmin * m[:, sub:sub+1])
    return out.reshape(b.shape[0], 256).ravel()[:n]

def deq_q6_k(raw, n):
    b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 210)
    ql = b[:, 0:128]; qh = b[:, 128:192]
    sc = b[:, 192:208].view(np.int8).astype(np.float32)
    d = _f16(b[:, 208:210])[:, None]
    out = np.empty((b.shape[0], 256), dtype=np.float32)
    l = np.arange(32)
    iss = l // 16
    for nn in range(2):
        ql0 = ql[:, nn*64:(nn+1)*64]; qh0 = qh[:, nn*32:(nn+1)*32]
        sc0 = sc[:, nn*8:(nn+1)*8]
        b1 = ql0[:, 0:32].astype(np.int16); b2 = ql0[:, 32:64].astype(np.int16)
        h = qh0.astype(np.int16)
        q1 = ((b1 & 0xF) | ((h & 3) << 4)) - 32
        q2 = ((b2 & 0xF) | (((h >> 2) & 3) << 4)) - 32
        q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32
        q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32
        base = nn * 128
        out[:, base + l]      = d * sc0[:, iss]     * q1.astype(np.float32)
        out[:, base + l + 32] = d * sc0[:, iss + 2] * q2.astype(np.float32)
        out[:, base + l + 64] = d * sc0[:, iss + 4] * q3.astype(np.float32)
        out[:, base + l + 96] = d * sc0[:, iss + 6] * q4.astype(np.float32)
    return out.ravel()[:n]

DEQ = {6: deq_q5_0, 8: deq_q8_0, 12: deq_q4_k, 13: deq_q5_k, 14: deq_q6_k}
