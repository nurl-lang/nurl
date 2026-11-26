#!/usr/bin/env python3
"""elab_parity_full.py CORE: a core IR's lines split as `nurl-cert words`
splits them (header lines at tabs, statements at whitespace, blank lines
dropped), with no line left out: the full words, as JSON, for
tools/ncore/elab_parity.sh to run `elabIR` on beside the words `nurl-cert
words` prints (which leave out a library function's statement lines)."""
import json
import re
import sys

t = open(sys.argv[1], encoding="utf-8").read()
rows = [l.split("\t") if l.startswith(("fn\t", "v\t", "ty\t", "sum\t"))
        else [w for w in re.split(r"[ \t]", l) if w]
        for l in t.split("\n") if l.strip(" ")]
json.dump(rows, sys.stdout)
