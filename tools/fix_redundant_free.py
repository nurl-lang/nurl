#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Remove release calls the compiler proves redundant.

`nurlc --lint` flags `( string_free x )`, `( vec_free [T] x )`, ... when x
is a local the compiler drops anyway and the call sits at the tail of a
block (only more such calls follow it, then `^` or the `}` of x's own
block) -- `[redundant-free]`. The drop at that point releases exactly what
the call did. This tool deletes those calls, compiling each file as the
top-level unit (the lint only speaks about the file being compiled), and
repeats until the compiler has nothing more to say.

    tools/fix_redundant_free.py [--nurlc build/nurlc] [--check] FILE.nu...

--check  report what would be removed and exit 1 if anything would be.
"""

import argparse
import os
import re
import subprocess
import sys

WARN = re.compile(r"^(.*?):(\d+):(\d+): warning: .*\[redundant-free\]$")


def lint(nurlc, path, root):
    env = dict(os.environ, NURL_STDLIB=root)
    r = subprocess.run([nurlc, "--lint", path], cwd=root, env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    hits = []
    for line in r.stderr.splitlines():
        m = WARN.match(line)
        if m and os.path.realpath(os.path.join(root, m.group(1))) == os.path.realpath(path):
            hits.append((int(m.group(2)), int(m.group(3))))
    return r.returncode, hits


def call_end(text, start):
    """Index just past the `)` matching the `(` at `start`."""
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c == "`":
            i = text.index("`", i + 1)
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced call")


def locate(line, col):
    """The `(` the compiler's column names — by character, else by byte."""
    if 0 < col <= len(line) and line[col - 1] == "(":
        return col - 1
    b = line.encode()
    if 0 < col <= len(b) and b[col - 1:col] == b"(":
        return len(b[:col - 1].decode())
    raise ValueError(f"no '(' at column {col}")


def remove(lines, hits):
    # Right to left, bottom to top: earlier offsets stay valid.
    for ln, col in sorted(hits, reverse=True):
        text = lines[ln - 1]
        start = locate(text, col)
        end = call_end(text, start)
        rest = text[:start].rstrip(" ") + (" " if text[:start].strip() and text[end:].strip() else "") + text[end:].lstrip(" ")
        if rest.strip() == "":
            lines[ln - 1] = None
        else:
            lines[ln - 1] = rest if rest.endswith("\n") else rest.rstrip(" ")
    return [l for l in lines if l is not None]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nurlc", default="build/nurlc")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    nurlc = os.path.realpath(a.nurlc)
    total, failed = 0, []
    for f in a.files:
        path = os.path.realpath(f)
        removed = 0
        for _ in range(10):
            code, hits = lint(nurlc, path, root)
            if not hits:
                break
            if a.check:
                for ln, col in hits:
                    print(f"{f}:{ln}:{col}: redundant release call")
                removed += len(hits)
                break
            with open(path, encoding="utf-8") as fh:
                lines = fh.read().split("\n")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("\n".join(remove(lines, hits)))
            removed += len(hits)
        if removed:
            code, _ = lint(nurlc, path, root)
            if code != 0 and not a.check:
                failed.append(f)
            print(f"{f}: {removed} call(s) {'redundant' if a.check else 'removed'}")
        total += removed
    print(f"total: {total}")
    if failed:
        print("no longer compiles:", *failed, file=sys.stderr)
        return 2
    return 1 if (a.check and total) else 0


if __name__ == "__main__":
    sys.exit(main())
