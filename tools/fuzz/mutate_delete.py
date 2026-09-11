#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  mutate_delete.py — delete one token, demand an answer.
#
#      python3 tools/fuzz/mutate_delete.py --files 40
#
#  Takes programs that compile, blanks one token at a time, and requires
#  the compiler to ANSWER each mutant: reject the file, or emit the
#  `main` the source still declares. A clean exit whose module has lost
#  main means the construct under the deleted token swallowed it; a
#  timeout means the parser spun.
#
#  Deletion is the mutation that matters here because it produces the
#  truncations people actually write — a missing brace, a missing
#  bracket — and the invariant needs no oracle to judge them.
#
#  Not a gate: a run is tens of thousands of compiles. It is a hunting
#  tool, like tools/diag_mutate.py, and its findings are programs to go
#  and read.
#
#  Two rules the harness enforces on itself, both learned the hard way:
#  it copies the corpus out of the tree and runs against a PRIVATE copy
#  of the compiler, so a concurrent ./build.sh cannot replace the binary
#  underneath it and its mutants can never be committed by accident.
# ============================================================
import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def tokens(src):
    """Token spans: backtick strings whole, comments skipped, everything
    else a word or a single punctuation character."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "`":
            j = src.find("`", i + 1)
            j = n if j < 0 else j + 1
            out.append((i, j))
            i = j
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if c.isspace():
            i += 1
            continue
        j = i
        if c.isalnum() or c == "_":
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
        else:
            j = i + 1
        out.append((i, j))
        i = j
    return out


def check_file(nurlc, path, workdir, timeout, findings):
    src = open(path).read()
    name = os.path.basename(path)
    for k, (a, b) in enumerate(tokens(src)):
        mutated = src[:a] + " " * (b - a) + src[b:]
        if not re.search(r"@\s*main\b", mutated):
            continue          # the deletion removed main itself
        tmp = os.path.join(workdir, ".mutant.nu")
        with open(tmp, "w") as f:
            f.write(mutated)
        try:
            r = subprocess.run([nurlc, tmp], capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            findings.append((name, k, src[a:b], "HANG", mutated))
            continue
        if r.returncode == 0 and b"define i32 @main(" not in r.stdout:
            findings.append((name, k, src[a:b], "exit 0, main never emitted", mutated))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", type=int, default=20, help="corpus programs to mutate")
    ap.add_argument("--seed", type=int, default=1, help="which programs (deterministic)")
    ap.add_argument("--timeout", type=int, default=30, help="seconds per compile")
    ap.add_argument("--nurlc", default=os.path.join(ROOT, "build", "nurlc"))
    ap.add_argument("--out", default=os.path.join(ROOT, "tools", "fuzz", "failures"))
    ap.add_argument("paths", nargs="*", help="specific .nu files (default: the corpus)")
    args = ap.parse_args()

    if not os.path.isfile(args.nurlc):
        print(f"mutate_delete: {args.nurlc} not built — run ./build.sh", file=sys.stderr)
        return 2

    work = tempfile.mkdtemp(prefix="mutate-delete-")
    try:
        # A private compiler: ./build.sh may replace build/nurlc mid-run.
        nurlc = os.path.join(work, "nurlc")
        shutil.copy2(args.nurlc, nurlc)

        if args.paths:
            sources = list(args.paths)
        else:
            tests = os.path.join(ROOT, "compiler", "tests")
            everything = sorted(f for f in os.listdir(tests) if f.endswith(".nu"))
            random.Random(args.seed).shuffle(everything)
            sources = [os.path.join(tests, f) for f in everything[: args.files]]

        # The corpus is copied out of the tree so a mutant can never be
        # left behind in it; siblings come along so their imports resolve.
        corpus = os.path.join(work, "corpus")
        os.makedirs(corpus, exist_ok=True)
        for f in os.listdir(os.path.join(ROOT, "compiler", "tests")):
            if f.endswith(".nu"):
                shutil.copy2(os.path.join(ROOT, "compiler", "tests", f), corpus)
        sources = [os.path.join(corpus, os.path.basename(p)) for p in sources]

        findings = []
        for n, path in enumerate(sources, 1):
            print(f"[{n}/{len(sources)}] {os.path.basename(path)}", flush=True)
            check_file(nurlc, path, corpus, args.timeout, findings)

        if findings:
            os.makedirs(args.out, exist_ok=True)
        for name, k, tok, why, mutated in findings:
            base = os.path.join(args.out, f"delete_{name[:-3]}_{k}.nu")
            with open(base, "w") as f:
                f.write(mutated)
            print(f"FINDING {name} token#{k} {tok!r} -> {why}  ({base})")
        print(f"{len(findings)} finding(s) over {len(sources)} program(s)")
        return 1 if findings else 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
