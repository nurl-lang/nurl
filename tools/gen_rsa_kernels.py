"""tools/gen_rsa_kernels.py — emit the width-specialised FIPS Montgomery
kernels of stdlib/std/rsa_mont.nu (__rm_mulN / __rm_sqrN).

    python3 tools/gen_rsa_kernels.py 16 > kernels.nu

Straight-line code: every column's products written out with fixed limb
indices, the a·b (or, squaring, the doubled cross) products and the q·m
reduction products summed in separate three-word accumulators so their
carry chains run side by side. The output replaces the block between the
markers in rsa_mont.nu; compiler/tests/rsa_mont_kernels holds it to
std/bigint.
"""
import sys

def mul_kernel(n):
    L = []
    L.append("// a·b·R^-1 into rp (n = %d limbs, not yet reduced below m); returns" % n)
    L.append("// the bit above them. Straight-line: tools/gen_rsa_kernels.py.")
    L.append("unsafe @ __rm_mul%d * i ap * i bp * i mp u64 n0 * i rp → u64 {" % n)
    for v in ("z", "x", "y"):
        for w in range(3):
            L.append("    : ~ u64 %s%d 0" % (v, w))
    for k in range(2 * n):
        ab = [(i, k - i) for i in range(max(0, k - n + 1), min(k, n - 1) + 1)]
        qm = [(i, k - i) for i in range(max(0, k - n + 1), min(k, n))]
        # two independent carry chains: a·b into x, q·m into y
        L.append("    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0")
        for (i, j) in ab:
            L.append("    ( __rm_acc x0 x1 x2 # u64 . ap %d # u64 . bp %d )" % (i, j))
        for (i, j) in qm:
            L.append("    ( __rm_acc y0 y1 y2 q%d # u64 . mp %d )" % (i, j))
        L.append("    ( __rm_add3 z0 z1 z2 x0 x1 x2 )")
        if qm:
            L.append("    ( __rm_add3 z0 z1 z2 y0 y1 y2 )")
        if k < n:
            L.append("    : u64 q%d * z0 n0" % k)
            L.append("    ( __rm_acc z0 z1 z2 q%d # u64 . mp 0 )" % k)
        else:
            L.append("    = . rp %d # i z0" % (k - n))
        L.append("    = z0 z1 = z1 z2 = z2 0")
    L.append("    ^ z0")
    L.append("}")
    return "\n".join(L)

def sqr_kernel(n):
    L = []
    L.append("// a²·R^-1 into rp, as __rm_mul%d with each column's cross products" % n)
    L.append("// summed once and doubled.")
    L.append("unsafe @ __rm_sqr%d * i ap * i mp u64 n0 * i rp → u64 {" % n)
    L.append("    : ~ u64 z0 0")
    L.append("    : ~ u64 z1 0")
    L.append("    : ~ u64 z2 0")
    for v in ("w", "y"):
        for t in range(3):
            L.append("    : ~ u64 %s%d 0" % (v, t))
    for k in range(2 * n):
        lo = max(0, k - n + 1)
        cross = [(i, k - i) for i in range(lo, n) if i < k - i]
        if cross:
            L.append("    = w0 0 = w1 0 = w2 0")
            for (i, j) in cross:
                L.append("    ( __rm_acc w0 w1 w2 # u64 . ap %d # u64 . ap %d )" % (i, j))
            L.append("    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )")
        qm = list(range(lo, min(k, n)))
        if qm:
            L.append("    = y0 0 = y1 0 = y2 0")
            for i in qm:
                L.append("    ( __rm_acc y0 y1 y2 q%d # u64 . mp %d )" % (i, k - i))
        if k % 2 == 0 and k // 2 < n:
            L.append("    ( __rm_acc z0 z1 z2 # u64 . ap %d # u64 . ap %d )" % (k // 2, k // 2))
        if qm:
            L.append("    ( __rm_add3 z0 z1 z2 y0 y1 y2 )")
        if k < n:
            L.append("    : u64 q%d * z0 n0" % k)
            L.append("    ( __rm_acc z0 z1 z2 q%d # u64 . mp 0 )" % k)
        else:
            L.append("    = . rp %d # i z0" % (k - n))
        L.append("    = z0 z1 = z1 z2 = z2 0")
    L.append("    ^ z0")
    L.append("}")
    return "\n".join(L)

if __name__ == "__main__":
    widths = [int(x) for x in sys.argv[1:]] or [16]
    out = []
    for n in widths:
        out.append(mul_kernel(n))
        out.append("")
        out.append(sqr_kernel(n))
        out.append("")
    sys.stdout.write("\n".join(out))
