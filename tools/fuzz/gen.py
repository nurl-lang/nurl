#!/usr/bin/env python3
# tools/fuzz/gen.py — random NURL integer-expression generator + oracle.
#
# Differential testing of nurlc's integer code generation. Each run emits a
# self-contained NURL program that computes K random expressions over the
# sized integer types and prints each result as its exact 64-bit pattern
# (16 hex digits, MSB first). The SAME generator computes the expected
# values itself (a trusted reference oracle implemented in Python with
# explicit two's-complement / width / signedness semantics), so a divergence
# between what the compiled program prints and what the oracle says is a
# miscompile — no second compiler needed.
#
# The generator is intentionally biased toward the historically buggy
# surface in nurlc: width coercions (`# T` trunc/sext/zext), unsigned
# arithmetic (udiv/urem/lshr/icmp u*), and mixed signed/unsigned operands.
#
# Usage:
#   gen.py SEED                  → prints the NURL program to stdout
#   gen.py SEED --oracle         → prints the expected stdout (K hex lines)
#   gen.py SEED --exprs N --depth D   (tunables)
#
# nurlc emits plain `add`/`mul`/`shl` (no nsw/nuw), so signed overflow is
# defined wrapping — the oracle wraps to match. Division/shift UB is avoided
# by construction (positive small divisors, shift amounts < width).

import sys
import random

# token -> (bit width, is_signed). `i` aliases i64, `u` is u8.
TYPES = {
    "i8":  (8,  True),
    "i16": (16, True),
    "i32": (32, True),
    "i64": (64, True),
    "u":   (8,  False),
    "u16": (16, False),
    "u32": (32, False),
    "u64": (64, False),
}
TYPE_NAMES = list(TYPES.keys())


def mask(w):
    return (1 << w) - 1


def wrap(value, ty):
    """Reduce a Python int to the value of NURL type `ty` (two's complement)."""
    w, signed = TYPES[ty]
    v = value & mask(w)
    if signed and (v >> (w - 1)) & 1:
        v -= (1 << w)
    return v


def to_u64_bits(value, ty):
    """The exact 64-bit pattern after `# i64 <value:ty>` — sext if the source
    is signed, zext if unsigned — matching nurlc's widening rule."""
    w, signed = TYPES[ty]
    v = wrap(value, ty)
    if signed:
        return v & mask(64)          # Python negative & mask == two's complement
    return v & mask(w)               # unsigned: zero-extended


# ── AST: each node carries its NURL type and knows how to (a) render to
#    source and (b) evaluate under the oracle. ──────────────────────────

class Node:
    def __init__(self, ty):
        self.ty = ty

    def render(self):
        raise NotImplementedError

    def eval(self):
        raise NotImplementedError


class Lit(Node):
    def __init__(self, ty, bits):
        super().__init__(ty)
        self.bits = bits            # non-negative bit pattern in [0, 2^w)

    def render(self):
        # A bare decimal literal is i64; `# T` truncates to the type width.
        return f"# {self.ty} {self.bits}"

    def eval(self):
        return wrap(self.bits, self.ty)


class Cast(Node):
    def __init__(self, ty, child):
        super().__init__(ty)
        self.child = child

    def render(self):
        return f"# {self.ty} {self.child.render()}"

    def eval(self):
        return wrap(self.child.eval(), self.ty)


class Bin(Node):
    def __init__(self, ty, op, a, b):
        super().__init__(ty)
        self.op, self.a, self.b = op, a, b

    def render(self):
        return f"{self.op} {self.a.render()} {self.b.render()}"

    def eval(self):
        w, signed = TYPES[self.ty]
        va, vb = self.a.eval(), self.b.eval()
        op = self.op
        if op == "+":
            r = va + vb
        elif op == "-":
            r = va - vb
        elif op == "*":
            r = va * vb
        elif op == "&":
            r = (va & mask(w)) & (vb & mask(w))
        elif op == "|":
            r = (va & mask(w)) | (vb & mask(w))
        elif op == "/":
            r = self._divrem(va, vb, signed, w, rem=False)
        elif op == "%":
            r = self._divrem(va, vb, signed, w, rem=True)
        elif op == "<<":
            r = (va & mask(w)) << vb
        elif op == ">>":
            if signed:
                r = va >> vb                      # Python >> on signed == ashr
            else:
                r = (va & mask(w)) >> vb           # lshr
        else:
            raise ValueError(op)
        return wrap(r, self.ty)

    @staticmethod
    def _divrem(va, vb, signed, w, rem):
        if signed:
            # C / LLVM sdiv/srem: truncate toward zero, srem takes dividend sign.
            a, b = va, vb
            q = abs(a) // abs(b)
            if (a < 0) != (b < 0):
                q = -q
            if not rem:
                return q
            return a - q * b
        else:
            ua, ub = va & mask(w), vb & mask(w)
            return ua % ub if rem else ua // ub


# ── Generator ───────────────────────────────────────────────────────────

class Gen:
    def __init__(self, rng):
        self.rng = rng

    def leaf(self, ty):
        w, _ = TYPES[ty]
        # 64-bit literals stay in non-negative i64 range to dodge literal
        # parsing edges; high-bit / negative 64-bit values still arise via
        # arithmetic, shifts, and widening casts from unsigned types.
        hi = (1 << 63) if w == 64 else (1 << w)
        return Lit(ty, self.rng.randrange(hi))

    def small_pos(self, ty):
        """A positive literal in [1, 63] — safe nonzero divisor / shift amount."""
        return Lit(ty, self.rng.randint(1, 63))

    def gen(self, ty, depth):
        if depth <= 0:
            return self.leaf(ty)
        kind = self.rng.choice(
            ["cast", "arith", "arith", "divrem", "bitwise", "shift", "leaf"]
        )
        if kind == "leaf":
            return self.leaf(ty)
        if kind == "cast":
            src = self.rng.choice(TYPE_NAMES)
            return Cast(ty, self.gen(src, depth - 1))
        if kind == "arith":
            op = self.rng.choice(["+", "-", "*"])
            return Bin(ty, op, self.gen(ty, depth - 1), self.gen(ty, depth - 1))
        if kind == "divrem":
            op = self.rng.choice(["/", "%"])
            return Bin(ty, op, self.gen(ty, depth - 1), self.small_pos(ty))
        if kind == "bitwise":
            op = self.rng.choice(["&", "|"])
            return Bin(ty, op, self.gen(ty, depth - 1), self.gen(ty, depth - 1))
        if kind == "shift":
            w, _ = TYPES[ty]
            op = self.rng.choice(["<<", ">>"])
            sh = Lit(ty, self.rng.randrange(w))   # 0..w-1, defined shift
            return Bin(ty, op, self.gen(ty, depth - 1), sh)
        raise AssertionError(kind)


PRELUDE = """\
// AUTO-GENERATED by tools/fuzz/gen.py — differential miscompile probe.
$ `stdlib/core/string.nu`

@ hexd i n → i { ? < n 10 { ^ + 48 n } { ^ + 87 n } }

// Print the exact 64-bit pattern of `v` as 16 hex digits, MSB first.
// `& 15 >> v (4*k)` extracts nibble k correctly for any k regardless of
// arithmetic vs logical shift (the mask discards sign-filled high bits).
@ phex i v → v {
    : String s ( string_new )
    : ~ i k 15
    ~ >= k 0 {
        ( string_push_char s ( hexd & 15 >> v * k 4 ) )
        = k - k 1
    }
    ( nurl_print ( string_data s ) )
    ( nurl_print `\\n` )
    ( string_free s )
}

@ main → i {
"""


def build(seed, n_exprs, depth):
    rng = random.Random(seed)
    g = Gen(rng)
    nodes = []
    for _ in range(n_exprs):
        ty = rng.choice(TYPE_NAMES)
        nodes.append((ty, g.gen(ty, depth)))
    return nodes


def emit_program(nodes):
    lines = [PRELUDE]
    for ty, node in nodes:
        lines.append(f"    ( phex # i64 {node.render()} )")
    lines.append("    ^ 0")
    lines.append("}")
    return "\n".join(lines) + "\n"


def emit_oracle(nodes):
    out = []
    for ty, node in nodes:
        bits = to_u64_bits(node.eval(), ty)
        out.append(f"{bits:016x}")
    return "\n".join(out) + "\n"


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: gen.py SEED [--oracle] [--exprs N] [--depth D]")
    seed = int(args[0])
    oracle = "--oracle" in args
    n_exprs = 12
    depth = 4
    if "--exprs" in args:
        n_exprs = int(args[args.index("--exprs") + 1])
    if "--depth" in args:
        depth = int(args[args.index("--depth") + 1])
    nodes = build(seed, n_exprs, depth)
    sys.stdout.write(emit_oracle(nodes) if oracle else emit_program(nodes))


if __name__ == "__main__":
    main()
