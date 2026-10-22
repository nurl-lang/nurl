#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_static_js.py — every script nurlapi serves must parse.
#
#  The playground (nurlapi/static/index.html) is one inline <script>.
#  #1209 removed a branch from an if/else-if chain and left a stray `}`;
#  a syntax error stops the whole script, so play.nurl-lang.org loaded
#  with no examples and a status badge stuck on "checking..." for every
#  visitor, while every endpoint behind it answered correctly. Nothing
#  ran the page's JavaScript before it shipped.
#
#  `node --check` on each inline script (as a module when it is one) and
#  on each .js file under nurlapi/static/. Parse only; nothing runs.
#
#  Usage: python3 tools/check_static_js.py [DIR ...]
# ============================================================
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = re.compile(r"<script\b([^>]*)>(.*?)</script\s*>", re.S | re.I)


def node_check(code, module):
    suffix = ".mjs" if module else ".js"
    with tempfile.NamedTemporaryFile("w", suffix=suffix, delete=False,
                                     encoding="utf-8") as f:
        f.write(code)
        path = f.name
    try:
        r = subprocess.run(["node", "--check", path],
                           capture_output=True, text=True)
        return r.returncode == 0, r.stderr.replace(path, "<script>")
    finally:
        os.unlink(path)


def main(dirs):
    checked = failed = 0
    for d in dirs:
        for name in sorted(os.listdir(d)):
            path = os.path.join(d, name)
            rel = os.path.relpath(path, ROOT)
            if name.endswith(".js"):
                ok, err = node_check(open(path, encoding="utf-8").read(),
                                     False)
                checked += 1
                if not ok:
                    failed += 1
                    print(f"FAIL {rel}\n{err}", file=sys.stderr)
                continue
            if not name.endswith(".html"):
                continue
            html = open(path, encoding="utf-8").read()
            for m in SCRIPT.finditer(html):
                attrs, code = m.group(1), m.group(2)
                if re.search(r"\bsrc\s*=", attrs) or not code.strip():
                    continue
                kind = re.search(r"\btype\s*=\s*[\"']?([^\"'\s>]+)", attrs)
                kind = kind.group(1).lower() if kind else ""
                if kind not in ("", "module", "text/javascript"):
                    continue    # JSON, importmap, templates: not scripts
                line = html.count("\n", 0, m.start(2)) + 1
                ok, err = node_check(code, kind == "module")
                checked += 1
                if not ok:
                    failed += 1
                    # node numbers lines from the script's first line
                    err = re.sub(r"<script>:(\d+)",
                                 lambda n: f"{rel}:{int(n.group(1)) + line - 1}",
                                 err)
                    print(f"FAIL {rel} (script at line {line})\n{err}",
                          file=sys.stderr)
    if failed:
        print(f"check_static_js: {failed} of {checked} script(s) do not parse",
              file=sys.stderr)
        return 1
    print(f"ok: {checked} script(s) parse")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or [os.path.join(ROOT, "nurlapi", "static")]))
