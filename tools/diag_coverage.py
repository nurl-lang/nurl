#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  diag_coverage.py — the analysis half of check_diag_coverage.sh.
#
#  Enumerates every diagnostic emission site in compiler/nurlc.nu and
#  reports which ones the test corpus has actually made speak.
#
#  Called by tools/check_diag_coverage.sh, which supplies the captured
#  stderr. Runnable directly for the long report:
#
#     python3 tools/diag_coverage.py compiler/nurlc.nu <errdir> report
#
#  Modes: summary | report | fingerprints | thin | json
# ============================================================
"""Diagnostic coverage over compiler/nurlc.nu.

A die site whose text never appears in any test's stderr is a message
nobody has read against a real program. Its wording is unverified, its
line/caret placement is unverified, and it may not even be reachable —
an earlier check can preempt it, leaving a written diagnostic dead.
Scanning the source cannot see any of that; only running the compiler
can. This is the half the source scan is blind to.
"""
import hashlib
import json
import os
import re
import sys
from collections import Counter

# Every emitter that puts a diagnostic in front of the user. die_if_void
# is not listed: it wraps `die` and its text is scanned at that site.
EMITTERS = ("die", "die_at", "die_stmt", "die_pos", "warn")

# A fingerprint has to be long enough not to collide with ordinary prose
# in some other message. 18 characters is past the point where two
# independently written diagnostics share a run by accident.
MIN_FINGERPRINT = 18


def mask_source(src):
    """Return a per-character map: 'c' code, 's' string, '#' comment.

    Paren balancing has to ignore parens inside backtick strings and
    `//` comments — a message that says "(the parenthesised form)" would
    otherwise close the call early and truncate the extracted text.
    """
    m = bytearray(b"c" * len(src))
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "`":
            j = src.find("`", i + 1)
            j = n if j < 0 else j + 1
            for k in range(i, j):
                m[k] = ord("s")
            i = j
        elif c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                m[k] = ord("#")
            i = j
        else:
            i += 1
    return m.decode()


def scan_sites(path):
    """Every diagnostic call site in `path`, with the text it can print."""
    src = open(path, encoding="utf-8").read()
    mask = mask_source(src)
    sites = []
    for m in re.finditer(r"\(\s*(%s)\s" % "|".join(EMITTERS), src):
        if mask[m.start()] != "c":
            continue  # the emitter's own name inside a comment or message
        depth, i = 0, m.start()
        while i < len(src):
            if mask[i] == "c":
                if src[i] == "(":
                    depth += 1
                elif src[i] == ")":
                    depth -= 1
                    if depth == 0:
                        break
            i += 1
        body = src[m.start():i + 1]
        lits = re.findall(r"`([^`]*)`", body)
        sites.append({
            "emitter": m.group(1),
            "line": src.count("\n", 0, m.start()) + 1,
            "text": norm(" ".join(lits)),
            "fingerprint": fingerprint(lits),
        })
    return sites


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def fingerprint(lits):
    """The longest literal run in a message — what to grep stderr for.

    None when every fragment is short or the whole message arrives in a
    variable: those sites are unmatchable by text and are reported
    separately rather than counted as uncovered, because a false "never
    fired" is worse than an honest gap in the instrument.
    """
    cands = sorted((norm(l) for l in lits), key=len, reverse=True)
    return next((c for c in cands if len(c) >= MIN_FINGERPRINT), None)


def site_key(site):
    """Line-independent identity, so the baseline survives edits above."""
    return hashlib.sha256(site["fingerprint"].encode("utf-8")).hexdigest()[:12]


def load_stderr(errdir):
    out = {}
    for fn in sorted(os.listdir(errdir)):
        if fn.endswith(".err"):
            with open(os.path.join(errdir, fn), encoding="utf-8",
                      errors="replace") as fh:
                out[fn[:-4]] = norm(fh.read())
    return out


def classify(sites, captured):
    covered, uncovered, unmatchable = [], [], []
    for s in sites:
        if s["fingerprint"] is None:
            unmatchable.append(s)
            continue
        s["hits"] = [k for k, v in captured.items() if s["fingerprint"] in v]
        (covered if s["hits"] else uncovered).append(s)
    return covered, uncovered, unmatchable


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "compiler/nurlc.nu"
    errdir = sys.argv[2] if len(sys.argv) > 2 else "build/diagcov"
    mode = sys.argv[3] if len(sys.argv) > 3 else "summary"

    sites = scan_sites(src)
    captured = load_stderr(errdir)
    covered, uncovered, unmatchable = classify(sites, captured)

    if mode == "fingerprints":
        # The baseline format: one `key  text` line per never-fired site,
        # sorted by key so the file is diff-stable across source edits.
        for s in sorted(uncovered, key=site_key):
            print(f"{site_key(s)}  {s['text'][:100]}")
        return 0

    if mode == "json":
        json.dump({"covered": covered, "uncovered": uncovered,
                   "unmatchable": unmatchable}, sys.stdout, indent=1)
        return 0

    if mode == "report":
        print(f"── never-fired diagnostics ({len(uncovered)}) "
              "─────────────────────────────")
        for s in sorted(uncovered, key=lambda x: x["line"]):
            print(f"{src}:{s['line']}: {s['emitter']}: {s['text'][:150]}")
        if unmatchable:
            print(f"\n── unmatchable by text ({len(unmatchable)}) "
                  "— message is built in a variable ──")
            for s in sorted(unmatchable, key=lambda x: x["line"]):
                print(f"{src}:{s['line']}: {s['emitter']}: "
                      f"{s['text'][:80] or '(no literal)'}")
        print()

    total = len(sites)
    print(f"diagnostic sites : {total}")
    print(f"  exercised      : {len(covered)}"
          f"  ({100 * len(covered) // max(total, 1)}%)")
    print(f"  never fired    : {len(uncovered)}")
    print(f"  unmatchable    : {len(unmatchable)}")
    print(f"  by emitter     : {dict(Counter(s['emitter'] for s in sites))}")
    print(f"  corpus files   : {len(captured)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
