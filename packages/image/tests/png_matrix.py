#!/usr/bin/env python3
# tests/png_matrix.py — hand-crafted PNG feature-matrix check.
#
# Writes PNGs covering every decode feature (bit depths 1/2/4/8/16, all
# colour types, Adam7 interlacing, tRNS palette alpha and colour keys) with
# a from-scratch encoder (Pillow cannot write most of these), runs the
# package's roundtrip binary on each, and compares its re-encoded 8-bit PNG
# against the expected RGBA pixels.
#
#   png_matrix.py gen  <dir>          — write <name>.png + <name>.expect.npy
#   png_matrix.py check <dir>         — compare <name>.out.png, exit 1 on any FAIL
import sys, os, zlib, struct
import numpy as np
from PIL import Image

ADAM7 = [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]

def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

def pack_row(samples, depth):
    """samples: flat list of ints for one row -> packed bytes."""
    if depth == 8:
        return bytes(samples)
    if depth == 16:
        out = bytearray()
        for s in samples: out += struct.pack(">H", s)
        return bytes(out)
    out, acc, nb = bytearray(), 0, 0
    for s in samples:
        acc = (acc << depth) | (s & ((1 << depth) - 1)); nb += depth
        if nb == 8: out.append(acc); acc, nb = 0, 0
    if nb: out.append(acc << (8 - nb))
    return bytes(out)

def write_png(path, W, H, depth, color, px, interlace=0, plte=None, trns=None):
    """px[y][x] = tuple of raw samples (len = channels for colour type)."""
    rch = {0:1, 2:3, 3:1, 4:2, 6:4}[color]
    raw = bytearray()
    if interlace == 0:
        passes = [(0,0,1,1)]
    else:
        passes = ADAM7
    for (x0, y0, dx, dy) in passes:
        pw = 0 if W <= x0 else (W - x0 + dx - 1)//dx
        ph = 0 if H <= y0 else (H - y0 + dy - 1)//dy
        if pw == 0 or ph == 0: continue
        for j in range(ph):
            row = []
            for i in range(pw):
                row.extend(px[y0 + j*dy][x0 + i*dx])
            raw += b"\x00" + pack_row(row, depth)
    ihdr = struct.pack(">IIBBBBB", W, H, depth, color, 0, 0, interlace)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
    if plte is not None:
        data += chunk(b"PLTE", bytes(v for rgb in plte for v in rgb))
    if trns is not None:
        data += chunk(b"tRNS", bytes(trns) if color == 3
                      else b"".join(struct.pack(">H", v) for v in trns))
    data += chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")
    with open(path, "wb") as f: f.write(data)

def scale(s, depth):
    return {1:255, 2:85, 4:17}.get(depth, 1) * s if depth < 8 else (s >> 8 if depth == 16 else s)

def gen(d):
    cases = []
    def expect_rgba(W, H, fn):
        a = np.zeros((H, W, 4), dtype=np.uint8)
        for y in range(H):
            for x in range(W): a[y, x] = fn(x, y)
        return a
    def add(name, W, H, depth, color, sample_fn, rgba_fn, interlace=0, plte=None, trns=None):
        px = [[sample_fn(x, y) for x in range(W)] for y in range(H)]
        write_png(f"{d}/{name}.png", W, H, depth, color, px, interlace, plte, trns)
        np.save(f"{d}/{name}.expect.npy", expect_rgba(W, H, rgba_fn))
        cases.append(name)

    # sub-8-bit + 16-bit greys
    add("g1", 13, 7, 1, 0, lambda x,y: ((x^y)&1,),
        lambda x,y: (scale((x^y)&1,1),)*3 + (255,))
    add("g2", 9, 5, 2, 0, lambda x,y: ((x+y)&3,),
        lambda x,y: (scale((x+y)&3,2),)*3 + (255,))
    add("g4", 10, 6, 4, 0, lambda x,y: ((x*3+y)&15,),
        lambda x,y: (scale((x*3+y)&15,4),)*3 + (255,))
    add("g16", 20, 9, 16, 0, lambda x,y: ((x*3000+y*700)&0xffff,),
        lambda x,y: (((x*3000+y*700)&0xffff)>>8,)*3 + (255,))
    # 16-bit colour / grey+alpha / RGBA
    add("rgb16", 11, 8, 16, 2, lambda x,y: ((x*5000)&0xffff,(y*6000)&0xffff,(x*y*997)&0xffff),
        lambda x,y: (((x*5000)&0xffff)>>8, ((y*6000)&0xffff)>>8, ((x*y*997)&0xffff)>>8, 255))
    add("ga16", 7, 9, 16, 4, lambda x,y: ((x*4000)&0xffff,(y*7000)&0xffff),
        lambda x,y: (((x*4000)&0xffff)>>8,)*3 + (((y*7000)&0xffff)>>8,))
    add("rgba16", 8, 5, 16, 6, lambda x,y: ((x*5000)&0xffff,(y*9000)&0xffff,(x*y*3111)&0xffff,((x+y)*4000)&0xffff),
        lambda x,y: (((x*5000)&0xffff)>>8, ((y*9000)&0xffff)>>8, ((x*y*3111)&0xffff)>>8, (((x+y)*4000)&0xffff)>>8))
    # palettes: 4-bit, and 8-bit with tRNS alpha
    pal = [((i*37)%256, (i*11)%256, (i*73)%256) for i in range(16)]
    add("pal4", 12, 10, 4, 3, lambda x,y: ((x+y*2)&15,),
        lambda x,y: pal[(x+y*2)&15] + (255,), plte=pal)
    pal2 = [((i*29)%256, (i*53)%256, (i*7)%256) for i in range(8)]
    tr = [255, 0, 128, 255, 64, 255, 255, 32]
    add("paltrns", 9, 6, 8, 3, lambda x,y: ((x+y)%8,),
        lambda x,y: pal2[(x+y)%8] + (tr[(x+y)%8],), plte=pal2, trns=tr)
    # colour keys
    add("gkey", 10, 4, 8, 0, lambda x,y: ((x*29+y*31)%256,),
        lambda x,y: ((x*29+y*31)%256,)*3 + (0 if (x*29+y*31)%256 == 60 else 255,), trns=[60])
    add("rgbkey", 8, 6, 8, 2, lambda x,y: (x*30%256, y*40%256, 77) if (x+y)%5 else (10, 20, 30),
        lambda x,y: ((x*30%256, y*40%256, 77, 255) if (x+y)%5 else (10, 20, 30, 0)), trns=[10,20,30])
    # Adam7 — odd sizes to exercise pass edges; sub-byte + palette+tRNS too
    add("adam_rgb", 21, 13, 8, 2, lambda x,y: (x*11%256, y*17%256, (x*y)%256),
        lambda x,y: (x*11%256, y*17%256, (x*y)%256, 255), interlace=1)
    add("adam_g1", 19, 11, 1, 0, lambda x,y: ((x*y+x)&1,),
        lambda x,y: (scale((x*y+x)&1,1),)*3 + (255,), interlace=1)
    add("adam_paltrns", 17, 9, 8, 3, lambda x,y: ((x*2+y)%8,),
        lambda x,y: pal2[(x*2+y)%8] + (tr[(x*2+y)%8],), plte=pal2, trns=tr)
    # tiny 1×1 and 2×2 interlaced (most passes empty)
    add("adam_tiny", 2, 2, 8, 2, lambda x,y: (x*100, y*100, 50),
        lambda x,y: (x*100, y*100, 50, 255), interlace=1)
    add("adam_rgba16", 9, 7, 16, 6, lambda x,y: ((x*7000)&0xffff,(y*8000)&0xffff,(x*y*5000)&0xffff,((x+y)*3000)&0xffff),
        lambda x,y: (((x*7000)&0xffff)>>8, ((y*8000)&0xffff)>>8, ((x*y*5000)&0xffff)>>8, (((x+y)*3000)&0xffff)>>8), interlace=1)
    with open(f"{d}/cases.txt", "w") as f: f.write("\n".join(cases))

def check(d):
    fails = 0
    for name in open(f"{d}/cases.txt").read().split():
        want = np.load(f"{d}/{name}.expect.npy")
        try:
            got = np.asarray(Image.open(f"{d}/{name}.out.png").convert("RGBA"), dtype=np.uint8)
        except Exception as e:
            print(f"  FAIL {name}: {e}"); fails += 1; continue
        if got.shape != want.shape:
            print(f"  FAIL {name}: shape {got.shape} vs {want.shape}"); fails += 1; continue
        # our decoder drops RGB under a fully-transparent colour-key pixel is
        # not a thing — everything must be exact
        if not np.array_equal(got, want):
            n = int((got != want).sum())
            print(f"  FAIL {name}: {n} byte diffs, first at {np.argwhere(got != want)[0]}"); fails += 1
        else:
            print(f"  PASS {name}")
    sys.exit(1 if fails else 0)

if __name__ == "__main__":
    {"gen": gen, "check": check}[sys.argv[1]](sys.argv[2])
