# Independent qwen2/gpt2 BPE reference: reads the GGUF vocab + merges itself,
# applies llama.cpp's pre-tokenizer regex, then merge-rank BPE.
import struct, sys
import regex as re

def read_gguf(path):
    d = open(path, 'rb').read(1 << 26)
    off = 8
    nt, nkv = struct.unpack_from('<QQ', d, off); off += 16
    kvs = {}
    def rs(o):
        n = struct.unpack_from('<Q', d, o)[0]; o += 8
        return d[o:o+n], o+n
    for _ in range(nkv):
        k, off = rs(off); vt = struct.unpack_from('<I', d, off)[0]; off += 4
        if vt == 8: v, off = rs(off)
        elif vt == 9:
            at = struct.unpack_from('<I', d, off)[0]; off += 4
            cnt = struct.unpack_from('<Q', d, off)[0]; off += 8
            v = []
            for _ in range(cnt):
                if at == 8: e, off = rs(off); v.append(e)
                elif at == 6: v.append(struct.unpack_from('<f', d, off)[0]); off += 4
                elif at in (4, 5): v.append(struct.unpack_from('<i', d, off)[0]); off += 4
                else: raise SystemExit('arr type %d' % at)
        elif vt in (4, 5, 6): v = struct.unpack_from('<I', d, off)[0]; off += 4
        elif vt == 7: v = d[off]; off += 1
        elif vt in (10, 11, 12): v = struct.unpack_from('<q', d, off)[0]; off += 8
        elif vt in (0, 1): v = d[off]; off += 1
        elif vt in (2, 3): v = struct.unpack_from('<H', d, off)[0]; off += 2
        else: raise SystemExit('vt %d' % vt)
        kvs[k.decode()] = v
    return kvs

kvs = read_gguf(sys.argv[1])
toks = [t.decode('utf-8', 'replace') for t in kvs['tokenizer.ggml.tokens']]
merges = [m.decode() for m in kvs['tokenizer.ggml.merges']]
pre = kvs.get('tokenizer.ggml.pre', b'default')
pre = pre.decode() if isinstance(pre, bytes) else pre
lut = {t: i for i, t in enumerate(toks)}
ranks = {m: i for i, m in enumerate(merges)}

def bytes_to_unicode():
    bs = list(range(33,127)) + list(range(161,173)) + list(range(174,256))
    cs = bs[:]; n = 0
    for b in range(256):
        if b not in bs:
            bs.append(b); cs.append(256+n); n += 1
    return dict(zip(bs, [chr(c) for c in cs]))
B2U = bytes_to_unicode()

QWEN2 = r"""(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"""
GPT2  = r"""'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"""
PAT = re.compile(QWEN2 if pre == 'qwen2' else GPT2)

def bpe(word):
    syms = list(word)
    while len(syms) > 1:
        best, br = -1, 1 << 30
        for i in range(len(syms) - 1):
            r = ranks.get(syms[i] + ' ' + syms[i+1])
            if r is not None and r < br: best, br = i, r
        if best < 0: break
        syms = syms[:best] + [syms[best] + syms[best+1]] + syms[best+2:]
    return syms

ids = []
for piece in PAT.findall(sys.stdin.read()):
    word = ''.join(B2U[b] for b in piece.encode('utf-8'))
    for sym in bpe(word):
        ids.append(lut.get(sym, kvs.get('tokenizer.ggml.unknown_token_id', 0)))
print(' '.join(map(str, ids)))
