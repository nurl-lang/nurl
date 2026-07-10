#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/gen_globals_map.py — regenerate the globals appendix of
#  docs/dev/COMPILER_INTERNALS.md from compiler/nurlc.nu.
#
#  For every module-level mutable global (`: ~ i g_*` / `: ~ s g_*`) it
#  records the declaration line, the declaration comment (trailing, or
#  the comment block immediately above), and the set of functions that
#  WRITE it (`= g_x …`, excluding ==/!=/<=/>= comparisons). Rewrites
#  everything after the "## 6." heading in place.
# ============================================================
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "compiler/nurlc.nu"
DOC = ROOT / "docs/dev/COMPILER_INTERNALS.md"
MARK = "## 6."

def build_table() -> str:
    src = SRC.read_text().splitlines()
    decl = {}
    for i, line in enumerate(src):
        g = re.match(r": ~ (?:i|s) (g_\w+)\s*(?://\s*(.*))?", line)
        if g:
            comment = g.group(2) or ""
            if not comment:
                j, cs = i - 1, []
                while j >= 0 and src[j].strip().startswith("//"):
                    cs.insert(0, src[j].strip()[2:].strip())
                    j -= 1
                comment = " ".join(cs)
            decl[g.group(1)] = (i + 1, comment[:110])

    writes = {g: set() for g in decl}
    fn = None
    for line in src:
        m = re.match(r"@ (\S+)", line)
        if m:
            fn = m.group(1)
        if fn is None:
            continue
        for g in set(re.findall(r"\bg_\w+\b", line)):
            # a write is `= g_x `, NOT the tail of ==/!=/<=/>=
            if g in decl and re.search(rf"(?<![=!<>])= {g} ", line):
                writes[g].add(fn)

    out = ["| global | declared | written by | holds |", "|---|---|---|---|"]
    for g, (ln, c) in sorted(decl.items()):
        w = sorted(writes[g])
        ws = ", ".join(f"`{x}`" for x in w[:4]) + (f" +{len(w)-4}" if len(w) > 4 else "")
        out.append(f"| `{g}` | :{ln} | {ws or '(init only)'} | {c.replace('|', chr(92)+'|')} |")
    return "\n".join(out) + "\n"

def main() -> int:
    doc = DOC.read_text()
    idx = doc.find(MARK)
    if idx < 0:
        print(f"gen_globals_map: '{MARK}' heading not found in {DOC}", file=sys.stderr)
        return 1
    # keep the heading + its intro paragraph (everything up to the table)
    tbl = doc.find("| global |", idx)
    if tbl < 0:
        print("gen_globals_map: existing table not found after the heading", file=sys.stderr)
        return 1
    DOC.write_text(doc[:tbl] + build_table())
    print(f"gen_globals_map: rewrote the appendix in {DOC}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
