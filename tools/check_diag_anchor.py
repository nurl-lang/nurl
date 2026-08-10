#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_diag_anchor.py — the analysis half of check_diag_anchor.sh.
#
#  Reads the committed goldens (they already hold `file:line:col:` plus
#  the echoed source line and caret) and reports diagnostics anchored
#  somewhere the mistake cannot be.
#
#  Runnable directly for the report:
#     python3 tools/check_diag_anchor.py compiler/tests report
# ============================================================
"""Where a diagnostic points, not what it says.

check_diag_coverage.sh answers "has anything ever printed this?".
It cannot answer "did it point at the right thing?" — and a precise
message against the wrong line is worse for a reader than a vague one
against the right line, because it sends them somewhere real to look for
a problem that is not there.

The objectively-wrong case is mechanical: an anchor line whose entire
content is closing delimiters. `}` is never the subject of a diagnostic;
it is where the parser noticed, one statement after the cause. Checks
that fire only once their operands are consumed land here by default,
which is what `die_stmt` and `die_pos` exist to prevent.

The second rule catches the same cause where the first cannot see it: a
caret printed past the end of the line it echoes points at nothing at
all, and that survives whenever the offending statement is not the last
one in its block.

Genuinely unterminated constructs are the exception to both and are
exempted by message text: when the closer is what went missing,
end-of-input IS the subject.
"""
import os
import re
import sys

# The whole content of an anchor line, when it is only structure.
CLOSERS_ONLY = re.compile(r"^[)\]}\s]+$")

# Messages whose subject really is the end of the input.
AT_EOF_OK = re.compile(
    r"\b(unterminated|unclosed|end of (file|input)|reached EOF|missing '\}')",
    re.I)

# `<path>:<line>:<col>: error|warning: <msg>` — the shape all four
# emitters print. die_at has no column and is skipped: with no column
# there is no caret to misplace.
DIAG = re.compile(r"^(?P<path>[^\s:]+\.nu):(?P<line>\d+):(?P<col>\d+): "
                  r"(?P<sev>error|warning): (?P<msg>.*)$")


def anchors(golden_path, tests_dir):
    """Every (test, line, col, msg) a golden records."""
    out = []
    with open(golden_path, encoding="utf-8", errors="replace") as fh:
        for rec in fh:
            m = DIAG.match(rec.rstrip("\n"))
            if not m:
                continue
            out.append({
                "golden": os.path.basename(golden_path),
                # repo-relative as the runner strips it; resolved by the caller
                "src": m.group("path"),
                "line": int(m.group("line")),
                "col": int(m.group("col")),
                "msg": m.group("msg"),
            })
    return out


def source_line(path, n):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for i, text in enumerate(fh, 1):
                if i == n:
                    return text.rstrip("\n")
    except OSError:
        return None
    return None


def check(tests_dir, repo_root):
    bad = []
    outdir = os.path.join(tests_dir, "outputs")
    for fn in sorted(os.listdir(outdir)):
        if not fn.endswith(".txt"):
            continue
        for a in anchors(os.path.join(outdir, fn), tests_dir):
            src = a["src"] if os.path.isabs(a["src"]) \
                else os.path.join(repo_root, a["src"])
            text = source_line(src, a["line"])
            if text is None:
                continue  # the diagnostic names a file the golden does not carry
            if AT_EOF_OK.search(a["msg"]):
                continue
            if CLOSERS_ONLY.match(text) and text.strip():
                a["text"] = text.strip()
                a["why"] = f'anchored on "{text.strip()}"'
                bad.append(a)
            elif a["col"] > len(text):
                # The caret is printed past the end of the line it echoes,
                # so it points at nothing at all. Same cause as the `}`
                # case — the check ran after the token was consumed — but
                # it survives when the statement is not the last one, so
                # the closing-delimiter rule alone does not see it.
                a["text"] = text.strip()
                a["why"] = (f'column {a["col"]} is past the end of a '
                            f'{len(text)}-character line')
                bad.append(a)
    return bad


def main():
    tests_dir = sys.argv[1] if len(sys.argv) > 1 else "compiler/tests"
    mode = sys.argv[2] if len(sys.argv) > 2 else "check"
    repo_root = os.path.abspath(os.path.join(tests_dir, "..", ".."))

    bad = check(tests_dir, repo_root)
    if mode == "keys":
        for a in sorted(bad, key=lambda x: (x["golden"], x["line"])):
            print(f'{a["golden"]}:{a["line"]}')
        return 0

    for a in sorted(bad, key=lambda x: (x["golden"], x["line"])):
        print(f'{a["src"]}:{a["line"]}:{a["col"]}: {a["why"]}')
        print(f'    {a["msg"][:150]}')
    print(f"\nmis-anchored diagnostics: {len(bad)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
