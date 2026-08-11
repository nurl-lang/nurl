#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  diag_mutate.py — one realistic mistake in a real program.
#
#     python3 tools/diag_mutate.py thread_basic dist_ring …
#
#  Prints, per mutant, how many diagnostics came out. Three outcomes
#  matter: exactly one (good), several (a cascade the reader must
#  triage), and NONE — a broken program the compiler accepted.
#
#  Not a gate. It is a hunting tool: the mutation set is a judgement
#  about what models get wrong, and the interesting result is always a
#  program to go and read, never a number to enforce.
# ============================================================
"""Mutation probe: one realistic mistake in a real program.

The corpus's negative tests are minimal by construction — the mistake IS
the program, so there is nothing after it to cascade into. A model writes
a hundred lines and gets one of them wrong, usually not the last one.
That is the case nothing has measured: does the compiler say one useful
thing, or does the broken parse state turn the rest of the file into
noise the reader has to triage before finding the real error?
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, "tools")
import importlib.util
_spec = importlib.util.spec_from_file_location("dc", "tools/diag_coverage.py")
_dc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_dc)


def code_only_spans(text):
    """Index ranges of `text` that are real code — not comment, not string.

    The first run of this probe reported six programs "accepted silently"
    after a mutation. Every one was the mutation landing inside a `//`
    comment: the program was unchanged, so compiling clean was correct.
    The instrument was wrong, not the compiler — the same masking lesson
    diag_coverage.py already carries, arrived at the same way.
    """
    mask = _dc.mask_source(text)
    return [i for i, m in enumerate(mask) if m == "c"]

NURLC = "build/nurlc"
DIAG = re.compile(r"^[^\s:]+\.nu:\d+:\d+: (error|warning): (.*)$")
TMP = os.environ.get("NURL_MUTATE_DIR", "build/diagmutate")

# Each mutation is (name, regex, replacement) applied to the FIRST match
# in the body — the mistakes a model actually makes, not random damage.
MUTATIONS = [
    ("ascii-arrow",     r"→",                     "->"),
    ("drop-arrow",      r" → ",                   " "),
    ("named-field",     r"@ (\w+) \{ ",           r"@ \1 { x : "),
    ("swap-type-name",  r"^(\s*): (i|b|f|s) (\w+) ", r"\1: \3 \2 "),
    ("drop-operand",    r"\+ (\w+) (\w+)",        r"+ \1"),
    ("drop-paren",      r"\( (\w+) ([^()]{0,20})\)", r"\1 \2"),
    ("wrong-ret-type",  r"→ i \{",                "→ s {"),
]


def diags(path):
    p = subprocess.run([NURLC, path], capture_output=True, text=True)
    return [m.group(2) for m in
            (DIAG.match(l) for l in p.stderr.splitlines()) if m]


def main(names):
    os.makedirs(TMP, exist_ok=True)
    rows = []
    for name in names:
        src_path = f"compiler/tests/{name}.nu"
        src = open(src_path, encoding="utf-8").read()
        for mname, pat, rep in MUTATIONS:
            # Mutate in the second half of the file's declarations, so the
            # damage has something after it to cascade into.
            lines = src.split("\n")
            half = len(lines) // 3
            head, tail = "\n".join(lines[:half]), "\n".join(lines[half:])
            code = set(code_only_spans(tail))
            new_tail, n = None, 0
            for m in re.finditer(pat, tail, flags=re.M):
                if m.start() not in code:
                    continue  # inside a comment or a string literal
                new_tail = tail[:m.start()] + m.expand(rep) + tail[m.end():]
                n = 1
                break
            if not n:
                continue
            out = os.path.join(TMP, f"{name}__{mname}.nu")
            open(out, "w", encoding="utf-8").write(head + "\n" + new_tail)
            ds = diags(out)
            rows.append((len(ds), name, mname, ds[0][:100] if ds else "(none)"))
    rows.sort(reverse=True)
    print(f"{'n':>3}  {'program':<22} {'mutation':<16} first diagnostic")
    for n, name, mname, first in rows:
        flag = "  ← cascade" if n > 1 else ("  ← SILENT" if n == 0 else "")
        print(f"{n:>3}  {name:<22} {mname:<16} {first}{flag}")
    print()
    print(f"mutants: {len(rows)}   "
          f"one diagnostic: {sum(1 for r in rows if r[0] == 1)}   "
          f"cascades: {sum(1 for r in rows if r[0] > 1)}   "
          f"accepted silently: {sum(1 for r in rows if r[0] == 0)}")


if __name__ == "__main__":
    main(sys.argv[1:])
