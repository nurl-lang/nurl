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

`--drop-temps` (AGORA-1030, CodeRabbit on #2331): the NURL translator binds
the temporary of an untracked number a statement consumes (a call's `c`
argument) around that statement, so a loop's round gets a fresh one;
tolean.py binds all of them once, at the top of the function body. With
the flag, every `(.letv q (.expr (.lit 0)) BODY)` whose variable q is never
assigned in its function (`(.assign q `) becomes BODY, on whichever side
it is applied to (apply it to both), and each function's dropped variables
are listed after the term (`-- dropped fnK: q1 q2 …`, sorted), so the
comparison still requires the same temporaries in each function, only not
where they are bound.
"""
import re
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


LETV0 = re.compile(r"\(\.letv (\d+) \(\.expr \(\.lit 0\)\) ")


def drop_temps_def(body):
    """One function's term without its never-assigned `.lit 0` bindings, and
    the variables dropped."""
    assigned = set(re.findall(r"\(\.assign (\d+) ", body))
    dropped = []
    while True:
        ms = [m for m in LETV0.finditer(body) if m.group(1) not in assigned]
        if not ms:
            return body, dropped
        m = ms[-1]   # innermost last: removing it keeps the outer ones' starts
        end = close(body, m.start())
        dropped.append(int(m.group(1)))
        body = body[:m.start()] + body[m.end():end - 1] + body[end:]


def drop_temps(s):
    out, trailer = [], []
    parts = re.split(r"(?m)^(?=def fn\d+ : Fn :=)", s)
    for part in parts:
        mh = re.match(r"def (fn\d+) : Fn :=", part)
        if not mh:
            out.append(part)
            continue
        body, dropped = drop_temps_def(part)
        out.append(body)
        trailer.append(f"-- dropped {mh.group(1)}: {' '.join(map(str, sorted(dropped)))}\n")
    return "".join(out) + "".join(trailer)


if __name__ == "__main__":
    args = sys.argv[1:]
    temps = "--drop-temps" in args
    args = [a for a in args if a != "--drop-temps"]
    text = open(args[0]).read() if args else sys.stdin.read()
    text = norm(text)
    sys.stdout.write(drop_temps(text) if temps else text)
