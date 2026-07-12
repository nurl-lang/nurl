# Independent ggml K-quant decoder straight from the GGUF bytes.
import struct, sys
import numpy as np

def read_gguf(path):
    d = np.memmap(path, dtype=np.uint8, mode='r')
    raw = bytes(d[:1<<22])
    off = 8
    nt, nkv = struct.unpack_from('<QQ', raw, off); off += 16
    def rs(off):
        n = struct.unpack_from('<Q', raw, off)[0]; off += 8
        return raw[off:off+n], off+n
    align = 32
    for _ in range(nkv):
        k, off = rs(off); vt = struct.unpack_from('<I', raw, off)[0]; off += 4
        if vt == 8: v, off = rs(off)
        elif vt == 9:
            at = struct.unpack_from('<I', raw, off)[0]; off += 4
            cnt = struct.unpack_from('<Q', raw, off)[0]; off += 8
            sz = {4:4,5:4,6:4,7:1,10:8,11:8,12:8,0:1,1:1,2:2,3:2}.get(at)
            if at == 8:
                for _ in range(cnt): _e, off = rs(off)
            else: off += sz*cnt
        elif vt in (4,5,6): off += 4
        elif vt == 7: off += 1
        elif vt in (10,11,12): off += 8
        elif vt in (0,1): off += 1
        elif vt in (2,3): off += 2
        if k == b'general.alignment': pass
    infos = []
    for _ in range(nt):
        nm, off = rs(off); nd = struct.unpack_from('<I', raw, off)[0]; off += 4
        dims = list(struct.unpack_from('<%dQ' % nd, raw, off)); off += 8*nd
        ty = struct.unpack_from('<I', raw, off)[0]; off += 4
        rel = struct.unpack_from('<Q', raw, off)[0]; off += 8
        infos.append((nm.decode(), dims, ty, rel))
    doff = (off + align - 1)//align*align
    return d, doff, infos

f16 = lambda b: np.frombuffer(b, dtype='<f2')[0].astype(np.float32)

def deq_q5_0(blk, n):
    out = np.zeros(n, dtype=np.float32)
    for i in range(n//32):
        b = blk[i*22:(i+1)*22]
        d = f16(b[0:2]); qh = int.from_bytes(b[2:6], 'little'); qs = b[6:22]
        for j in range(16):
            h0 = ((qh >> j) & 1) << 4
            h1 = ((qh >> (j+16)) & 1) << 4
            out[i*32+j]    = d * (((qs[j] & 0xF) | h0) - 16)
            out[i*32+16+j] = d * (((qs[j] >> 4)  | h1) - 16)
    return out

def deq_q8_0(blk, n):
    out = np.zeros(n, dtype=np.float32)
    for i in range(n//32):
        b = blk[i*34:(i+1)*34]
        d = f16(b[0:2]); q = np.frombuffer(b[2:34], dtype=np.int8)
        out[i*32:(i+1)*32] = d * q.astype(np.float32)
    return out

def get_scale_min_k4(j, sc):
    if j < 4: return sc[j] & 63, sc[j+4] & 63
    return (sc[j+4] & 0xF) | ((sc[j-4] >> 6) << 4), (sc[j+4] >> 4) | ((sc[j] >> 6) << 4)

def deq_q4_k(blk, n):
    out = np.zeros(n, dtype=np.float32); o = 0
    for i in range(n//256):
        b = blk[i*144:(i+1)*144]
        d = f16(b[0:2]); dmin = f16(b[2:4]); sc = b[4:16]; q = b[16:144]
        for sub in range(8):
            s, m = get_scale_min_k4(sub, sc)
            d1 = d * s; m1 = dmin * m
            half = sub // 2; hi = sub % 2
            for l in range(32):
                byte = q[half*32 + l]
                v = (byte >> 4) if hi else (byte & 0xF)
                out[o] = d1 * v - m1; o += 1
    return out

def deq_q5_k(blk, n):
    out = np.zeros(n, dtype=np.float32); o = 0
    for i in range(n//256):
        b = blk[i*176:(i+1)*176]
        d = f16(b[0:2]); dmin = f16(b[2:4]); sc = b[4:16]; qh = b[16:48]; q = b[48:176]
        for sub in range(8):
            s, m = get_scale_min_k4(sub, sc)
            d1 = d * s; m1 = dmin * m
            half = sub // 2; hi = sub % 2
            for l in range(32):
                byte = q[half*32 + l]
                v = (byte >> 4) if hi else (byte & 0xF)
                hbit = (qh[l] >> sub) & 1
                out[o] = d1 * (v + (hbit << 4)) - m1; o += 1
    return out

def deq_q6_k(blk, n):
    out = np.zeros(n, dtype=np.float32)
    for i in range(n//256):
        b = blk[i*210:(i+1)*210]
        ql = b[0:128]; qh = b[128:192]
        sc = np.frombuffer(b[192:208], dtype=np.int8); d = f16(b[208:210])
        for nn in range(2):
            for l in range(32):
                iss = l // 16
                qhv = qh[nn*32 + l]
                b1 = ql[nn*64 + l]; b2 = ql[nn*64 + l + 32]
                q1 = ((b1 & 0xF) | ((qhv & 3) << 4)) - 32
                q2 = ((b2 & 0xF) | (((qhv >> 2) & 3) << 4)) - 32
                q3 = ((b1 >> 4)  | (((qhv >> 4) & 3) << 4)) - 32
                q4 = ((b2 >> 4)  | (((qhv >> 6) & 3) << 4)) - 32
                base = i*256 + nn*128 + l
                out[base]      = d * sc[nn*8 + iss]     * q1
                out[base + 32] = d * sc[nn*8 + iss + 2] * q2
                out[base + 64] = d * sc[nn*8 + iss + 4] * q3
                out[base + 96] = d * sc[nn*8 + iss + 6] * q4
    return out

DEQ = {6: deq_q5_0, 8: deq_q8_0, 12: deq_q4_k, 13: deq_q5_k, 14: deq_q6_k}
data, doff, infos = read_gguf(sys.argv[1])
want = sys.argv[2]
for nm, dims, ty, rel in infos:
    if nm == want:
        n = int(np.prod(dims))
        blk = bytes(data[doff+rel: doff+rel + n * {6:22,8:34,12:144,13:176,14:210}[ty] // {6:32,8:32,12:256,13:256,14:256}[ty]])
        out = DEQ[ty](blk, n)
        out.astype('<f4').tofile(sys.argv[3])
        print("%s type=%d n=%d" % (nm, ty, n))
        break
