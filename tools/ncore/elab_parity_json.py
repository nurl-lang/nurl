#!/usr/bin/env python3
"""elab_parity_json.py: `nurl-cert words`'s Lean literal (`def ir : C.Elab.IR
:= [ … ]`) as JSON, for tools/ncore/elab_parity.sh.

The literal is parsed, not repaired: a list of lines, each a list of words,
each word `nat_lit 0x1` and then hex digits in pairs (the word's bytes, last
to first: words.nu's form), with commas exactly between elements (none
trailing), whitespace only between tokens, and nothing after the closing
bracket but a newline. Each word is written to the JSON as its number. Any
other shape is refused with exit status 1. A literal this refuses is never
classified, so it can not be read differently from the Lean literal the
kernel stage reads."""
import json
import sys

HEAD = "def ir : C.Elab.IR := "
WORD = "nat_lit 0x1"
HEX = "0123456789abcdef"


class Bad(Exception):
    pass


class P:
    def __init__(self, t):
        self.t, self.i = t, 0

    def ws(self):
        while self.i < len(self.t) and self.t[self.i] in " \n":
            self.i += 1

    def eat(self, c):
        self.ws()
        if self.i >= len(self.t) or self.t[self.i] != c:
            got = self.t[self.i] if self.i < len(self.t) else "end of file"
            raise Bad("expected %r at offset %d, found %r" % (c, self.i, got))
        self.i += 1

    def peek(self):
        self.ws()
        return self.t[self.i] if self.i < len(self.t) else ""

    def seq(self, item):
        """`[` item (`,` item)* `]`, or `[` `]`."""
        self.eat("[")
        out = []
        if self.peek() == "]":
            self.i += 1
            return out
        while True:
            out.append(item())
            if self.peek() == ",":
                self.i += 1
                continue
            self.eat("]")
            return out

    def word(self):
        self.ws()
        t = self.t
        if not t.startswith(WORD, self.i):
            raise Bad("expected a word (%r) at offset %d" % (WORD, self.i))
        self.i += len(WORD)
        a = self.i
        while self.i < len(t) and t[self.i] in HEX:
            self.i += 1
        h = t[a:self.i]
        if len(h) % 2:
            raise Bad("a word with an odd number of hex digits at offset %d" % a)
        return int("1" + h, 16)

    def line(self):
        return self.seq(self.word)


def main(path):
    t = open(path, encoding="ascii").read()
    if not t.startswith(HEAD):
        raise Bad("not a words literal")
    p = P(t)
    p.i = len(HEAD)
    lines = p.seq(p.line)
    if t[p.i:] not in ("", "\n"):
        raise Bad("text after the literal at offset %d" % p.i)
    json.dump(lines, sys.stdout)


try:
    main(sys.argv[1])
except (Bad, OSError, UnicodeDecodeError) as e:
    sys.stderr.write("elab_parity_json.py: %s: %s\n" % (sys.argv[1], e))
    sys.exit(1)
