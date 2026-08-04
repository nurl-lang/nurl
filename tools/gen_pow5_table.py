#!/usr/bin/env python3
"""Generate stdlib/nurl_pow5_table.h — the power-of-five tables the
shortest round-trip float formatter in stdlib/runtime_core.c multiplies by.

Both tables hold 125-bit fixed-point values as a (low 64, high 64) pair:

  NURL_POW5[i]      = the top 125 bits of 5^i, i.e.
                      floor(5^i / 2^(ceil(log2(5^i)) - 125))
  NURL_POW5_INV[i]  = ceil(2^(124 + ceil(log2(5^i))) / 5^i), computed as
                      floor(...) + 1

They are exact by construction — the 125-bit width is what makes the
truncated 128-bit product in `nurl__mul_shift` equal to the exact
floor(m * 5^±q / 2^j) for every m the formatter feeds it (m < 2^55).

Run from the repo root:  python3 tools/gen_pow5_table.py
The output is committed; regenerate only if the bit counts change.
"""
import os
import sys

POW5_BITCOUNT = 125
POW5_INV_BITCOUNT = 125
POW5_N = 326       # 5^i for i in [0, 325]  — covers e2 down to -1076
POW5_INV_N = 292   # 5^-i for i in [0, 291] — covers e2 up to 971

HEADER = """/*
 * NURL runtime — stdlib/nurl_pow5_table.h   (GENERATED, do not edit)
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Regenerate with:  python3 tools/gen_pow5_table.py
 *
 * 125-bit fixed-point powers of five for the shortest round-trip decimal
 * conversion in runtime_core.c (§2b). Each entry is { low 64, high 64 }.
 *
 *   NURL_POW5[i]     = floor(5^i / 2^(ceil(log2(5^i)) - %(p5)d))
 *   NURL_POW5_INV[i] = floor(2^(%(p5inv)d - 1 + ceil(log2(5^i))) / 5^i) + 1
 *
 * %(n5)d + %(n5inv)d entries = %(kb)s KiB of rodata.
 */
"""


def emit(name, values, n):
    lines = [f"static const uint64_t {name}[{n}][2] = {{"]
    for v in values:
        lo = v & ((1 << 64) - 1)
        hi = v >> 64
        assert hi < (1 << 64), "entry wider than 128 bits"
        lines.append(f"    {{ {lo}ULL, {hi}ULL }},")
    lines.append("};")
    return "\n".join(lines)


def main():
    pow5 = []
    for i in range(POW5_N):
        p = 5 ** i
        shift = p.bit_length() - POW5_BITCOUNT
        pow5.append(p << -shift if shift < 0 else p >> shift)

    pow5_inv = []
    for i in range(POW5_INV_N):
        p = 5 ** i
        j = p.bit_length() - 1 + POW5_INV_BITCOUNT
        pow5_inv.append(((1 << j) // p) + 1)

    out = HEADER % dict(p5=POW5_BITCOUNT, p5inv=POW5_INV_BITCOUNT,
                        n5=POW5_N, n5inv=POW5_INV_N,
                        kb=round((POW5_N + POW5_INV_N) * 16 / 1024, 1))
    out += "\n#define NURL_POW5_BITCOUNT     %d\n" % POW5_BITCOUNT
    out += "#define NURL_POW5_INV_BITCOUNT %d\n\n" % POW5_INV_BITCOUNT
    out += emit("NURL_POW5", pow5, POW5_N) + "\n\n"
    out += emit("NURL_POW5_INV", pow5_inv, POW5_INV_N) + "\n"

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, "stdlib", "nurl_pow5_table.h")
    with open(path, "w") as f:
        f.write(out)
    sys.stderr.write("wrote %s (%d bytes)\n" % (path, len(out)))


if __name__ == "__main__":
    main()
