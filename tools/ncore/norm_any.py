#!/usr/bin/env python3
"""norm_any.py [file]: the NURL translator's Lean term in tolean.py's spelling.

AGORA-1030: the NURL translator (packages/nurl-cert/src/tolean.nu) writes a
number the core IR does not track as `.any` (any value), where the frozen
reference tools/ncore/tolean.py writes `(.lit 0)`. A scalar computation
over tracked operands `e` is `(.add .any (.lt e (.lit 0)))`, any number
with its operands still read, where tolean.py writes `e`. This rewrites the
first spelling into the second, so the parity checks (tolean_parity.sh,
tests/translate_test.sh) compare everything else byte for byte. Reads a
file or stdin and writes stdout. Off the certificate path.
"""
import sys

WRAP = "(.add .any (.lt "


def close(s, i):
    """The index just past the parenthesised term that starts at s[i] == '('."""
    d = 0
    for j in range(i, len(s)):
        if s[j] == "(":
            d += 1
        elif s[j] == ")":
            d -= 1
            if d == 0:
                return j + 1
    raise ValueError("unbalanced parentheses")


def norm(s):
    out, i = [], 0
    while i < len(s):
        if s.startswith(WRAP, i):
            a = i + len(WRAP)
            if s[a] == "(":
                b = close(s, a)
                tail = " (.lit 0)))"
                if s.startswith(tail, b):
                    out.append(norm(s[a:b]))
                    i = b + len(tail)
                    continue
        # (`.fn [ms] .any` is the closure class Cross.any, not Expr.any)
        if (s.startswith(".any", i) and not (s[i + 4:i + 5].isalnum() or s[i + 4:i + 5] == "_")
                and not s[:i].endswith("] ")):
            out.append("(.lit 0)")
            i += 4
            continue
        out.append(s[i])
        i += 1
    return "".join(out)


if __name__ == "__main__":
    text = open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read()
    sys.stdout.write(norm(text))
