#!/usr/bin/env python3
"""elab_parity_json.py: `nurl-cert words`'s Lean literal (`def ir : C.Elab.IR
:= [ … ]`) as JSON, for tools/ncore/elab_parity.sh. The words are kept as
they are: only the literal's escapes (`\\"`, `\\\\`, `\\xHH`, the only ones
words.nu writes) are rewritten as JSON's. Anything else is refused."""
import json
import sys

HEAD = "def ir : C.Elab.IR := "


def main(path):
    t = open(path, encoding="utf-8").read()
    if not t.startswith(HEAD):
        sys.exit("not a words literal: " + path)
    t = t[len(HEAD):]
    out, i, n = [], 0, len(t)
    lines, cur, depth = [], None, 0
    while i < n:
        c = t[i]
        if c == "[":
            depth += 1
            if depth == 2:
                cur = []
            elif depth > 2:
                sys.exit("nested too deep")
        elif c == "]":
            if depth == 2:
                lines.append(cur)
                cur = None
            depth -= 1
        elif c == '"':
            if depth != 2:
                sys.exit("a word outside a line")
            i += 1
            w = []
            while t[i] != '"':
                if t[i] == "\\":
                    e = t[i + 1]
                    if e in '"\\':
                        w.append(e); i += 2
                    elif e == "x":
                        w.append(chr(int(t[i + 2:i + 4], 16))); i += 4
                    else:
                        sys.exit("an escape words.nu does not write: \\" + e)
                else:
                    w.append(t[i]); i += 1
            cur.append("".join(w))
        elif c in ", \n":
            pass
        else:
            sys.exit("unexpected character %r" % c)
        i += 1
    if depth != 0:
        sys.exit("unbalanced")
    json.dump(lines, sys.stdout)


main(sys.argv[1])
