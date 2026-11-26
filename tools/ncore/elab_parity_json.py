#!/usr/bin/env python3
"""elab_parity_json.py: `nurl-cert words`'s Lean literal (`def ir : C.Elab.IR
:= [ … ]`) as JSON, for tools/ncore/elab_parity.sh.

The literal is parsed, not repaired: a list of lines, each a list of string
words, with commas exactly between elements (none trailing), whitespace
only between tokens, and nothing after the closing bracket but a newline.
In a word, only the escapes words.nu writes (`\\"`, `\\\\`, `\\xHH`) are
rewritten; any other escape, a control character, or any other shape is
refused with exit status 1. A literal this refuses is never classified, so
it can not be read differently from the Lean literal the kernel stage
reads."""
import json
import sys

HEAD = "def ir : C.Elab.IR := "
HEX = "0123456789abcdefABCDEF"


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
        self.eat('"')
        t, w = self.t, []
        while True:
            if self.i >= len(t):
                raise Bad("a word not closed")
            c = t[self.i]
            if c == '"':
                self.i += 1
                return "".join(w)
            if c == "\\":
                e = t[self.i + 1:self.i + 2]
                if e in ('"', "\\"):
                    w.append(e)
                    self.i += 2
                elif e == "x":
                    h = t[self.i + 2:self.i + 4]
                    if len(h) != 2 or any(x not in HEX for x in h):
                        raise Bad("a \\x escape without two hex digits at offset %d" % self.i)
                    w.append(chr(int(h, 16)))
                    self.i += 4
                else:
                    raise Bad("an escape words.nu does not write: \\" + e)
            elif ord(c) < 0x20:
                raise Bad("a control character in a word at offset %d" % self.i)
            else:
                w.append(c)
                self.i += 1

    def line(self):
        return self.seq(self.word)


def main(path):
    t = open(path, encoding="utf-8").read()
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
