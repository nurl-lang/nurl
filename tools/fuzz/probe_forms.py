#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Ask two questions of a list of hand-written source forms.

    1. does nurlc reject it?
    2. if it exits 0, does clang accept the IR it emitted?

This is the exploratory tool the 2026-09-12 sweep of the `&`-FFI, `\\`
try-propagation, `?T` / `!T E`, `#` cast, select/channel and Send/Sync
surfaces was written with. It is NOT a gate — a form's expectation is
optional and nothing fails the build. Once a form has an answer worth
keeping, move it into `tools/tests/test_declaration_forms.py`, which runs
the same two questions as an assertion.

Usage:  python3 tools/fuzz/probe_forms.py FORMS.py
where FORMS.py defines

    FORMS = [(name, source), ...]              # or (name, source, expected)
    SIDE_FILES = {"lib.nu": "..."}             # optional siblings to import

Verdicts: OK (compiles, clang accepts, main present), REJECT (nurlc said
no), CLANG-REJECT (exit 0, IR clang refuses), NO-MAIN (exit 0, main gone),
TIMEOUT, and HARNESS.

**HARNESS is the point of this file.** A probe that cannot tell "rejected
for the reason under test" from "never ran" reports whatever you hoped
for, and that mistake has landed three rounds running in three spellings:
an unresolved `$` import (exit 1), `clang -fsyntax-only -x ir` (which does
not parse IR at all and exits 0 on a module llvm-as rejects — note the
`clang -c` below), and a baseline compiler that failed to LINK because a
sanitized build had replaced `stdlib/runtime.o` underneath it (exit 127).
So an unresolved import is reported as HARNESS, never as REJECT. Add a
case here for every new way a run can fail to be a run.
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NURLC = os.environ.get("NURLC", os.path.join(ROOT, "build", "nurlc"))


def run(src, d):
    path = os.path.join(d, "a.nu")
    with open(path, "w") as f:
        f.write(src)
    # NURL_STDLIB so a form may '$'-import the tree from the scratch dir.
    env = dict(os.environ, NURL_STDLIB=ROOT)
    r = subprocess.run([NURLC, "a.nu"], capture_output=True, timeout=120,
                       cwd=d, env=env)
    if r.returncode != 0:
        err = r.stderr.decode("utf-8", "replace")
        if "cannot open import" in err:
            return "HARNESS", err.strip().splitlines()[0][:150]
        lines = err.strip().splitlines()
        return "REJECT", (lines[0][:150] if lines else "(no message)")
    ll = os.path.join(d, "a.ll")
    with open(ll, "wb") as f:
        f.write(r.stdout)
    try:
        c = subprocess.run(
            ["clang", "-c", "-Wno-override-module", ll, "-o", os.path.join(d, "a.o")],
            capture_output=True, timeout=120, cwd=d)
    except FileNotFoundError:
        return "HARNESS", "clang not on PATH — the second question was not asked"
    if c.returncode != 0:
        errs = [l for l in c.stderr.decode("utf-8", "replace").splitlines()
                if "error:" in l]
        return "CLANG-REJECT", (errs[0][:150] if errs else "clang refused the module")
    if b"define i32 @main(" not in r.stdout:
        return "NO-MAIN", ""
    return "OK", ""


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    if not os.path.isfile(NURLC):
        print(f"probe_forms: {NURLC} not built — run ./build.sh", file=sys.stderr)
        return 2
    ns = {}
    with open(argv[1]) as f:
        exec(f.read(), ns)  # noqa: S102 — a local form list, by design
    side = ns.get("SIDE_FILES", {})
    surprises = 0
    for entry in ns["FORMS"]:
        name, src = entry[0], entry[1]
        want = entry[2] if len(entry) > 2 else None
        with tempfile.TemporaryDirectory() as d:
            for fname, content in side.items():
                with open(os.path.join(d, fname), "w") as f:
                    f.write(content)
            try:
                verdict, msg = run(src, d)
            except subprocess.TimeoutExpired:
                verdict, msg = "TIMEOUT", ""
        flag = ""
        if want and want != verdict:
            flag = f"   <<< expected {want}"
            surprises += 1
        print(f"{verdict:14s} {name:40s} {msg}{flag}")
    if surprises:
        print(f"\n{surprises} form(s) did not match their expectation.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
