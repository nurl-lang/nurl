#!/usr/bin/env python3
"""elab_parity_full.py CORE: a core IR's lines split as `nurl-cert words`
splits them (header lines at tabs, statements at spaces and tabs, blank
lines dropped), with no line left out: the full words, as JSON, each word
its number as words.nu writes it (256^k + its k bytes, the first the
lowest), for tools/ncore/elab_parity.sh to run `elabIR` on beside the words
`nurl-cert words` prints (which leave out a library function whose records
the reader reads, and the `sum` lines no other word names)."""
import json
import re
import sys

# A word is a number of 8 bits a byte: a 2000-byte word has ~4800 decimal
# digits, past CPython's default limit (4300) for writing one in decimal,
# which json.dump does.
if hasattr(sys, "set_int_max_str_digits"):
    sys.set_int_max_str_digits(0)


def num(w):
    return 256 ** len(w) + int.from_bytes(w[::-1], "big")


t = open(sys.argv[1], "rb").read()
rows = [[num(w) for w in (l.split(b"\t") if l.startswith((b"fn\t", b"v\t", b"ty\t", b"sum\t"))
                          else [w for w in re.split(rb"[ \t]", l) if w])]
        for l in t.split(b"\n") if l.strip(b" ")]
json.dump(rows, sys.stdout)
