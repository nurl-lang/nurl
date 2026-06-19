#!/usr/bin/env python3
"""
bench/genacc/score.py — compile and run model-generated solutions and
score them on two axes:

  * first-pass COMPILE success — did the generated program build at all,
    with zero human edits?
  * CORRECT output — did it print exactly the expected bytes?

This is the affirmative side of the LLM-native thesis: if NURL's regular,
locally-decodable grammar helps, it shows up as a higher first-pass
compile (and correct) rate than mainstream languages on matched tasks —
the dimension the token-count study (bench/TOKEN_EFFICIENCY.md) does NOT
measure.

    python3 bench/genacc/score.py claude-sonnet-4-6      # score one model dir
    python3 bench/genacc/score.py --md results.md ...    # also write markdown

Solutions are read from bench/genacc/solutions/<model>/run*/<task>.<ext>.
Nothing here calls a model; generate.py does that.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
NURLC = ROOT / "build" / "nurlc"
RUNTIME = ROOT / "stdlib" / "runtime.o"
BUILD = HERE / "_build"

RUN_TIMEOUT = 90  # seconds; lcg/sieve are ~tens of seconds in slow langs

LANG_EXT = {"nurl": "nu", "python": "py", "rust": "rs", "node": "js"}
EXT_LANG = {v: k for k, v in LANG_EXT.items()}


def feature_libs() -> list[str]:
    libs: list[str] = []
    for sentinel, pkg in [("runtime.curl", "libcurl"), ("runtime.openssl", "openssl"),
                          ("runtime.sqlite3", "sqlite3"), ("runtime.pq", "libpq"),
                          ("runtime.z", "zlib"), ("runtime.zstd", "libzstd")]:
        if (ROOT / "stdlib" / sentinel).exists():
            try:
                out = subprocess.run(["pkg-config", "--libs", pkg],
                                     capture_output=True, text=True)
                libs += out.stdout.split()
            except FileNotFoundError:
                pass
    return libs


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def build_and_run(lang: str, src: Path, name: str) -> tuple[bool, str | None]:
    """Return (compiled, output_or_None). output None means run failed."""
    BUILD.mkdir(exist_ok=True)
    if lang == "nurl":
        ll = BUILD / f"{name}.ll"
        binp = BUILD / f"{name}_nurl"
        r = sh([str(NURLC), str(src)], cwd=str(ROOT))
        if r.returncode != 0:
            return False, None
        ll.write_text(r.stdout)
        link = sh(["clang", "-O2", "-flto", str(ll), str(RUNTIME),
                   "-lm", "-lpthread", *feature_libs(), "-o", str(binp)])
        if link.returncode != 0:
            return False, None
        try:
            run = sh([str(binp)], cwd=str(ROOT), timeout=RUN_TIMEOUT)
        except subprocess.TimeoutExpired:
            return True, None
        return True, run.stdout if run.returncode == 0 else None
    if lang == "python":
        chk = sh([sys.executable, "-m", "py_compile", str(src)])
        if chk.returncode != 0:
            return False, None
        try:
            run = sh([sys.executable, str(src)], timeout=RUN_TIMEOUT)
        except subprocess.TimeoutExpired:
            return True, None
        return True, run.stdout if run.returncode == 0 else None
    if lang == "rust":
        binp = BUILD / f"{name}_rs"
        c = sh(["rustc", "-O", str(src), "-o", str(binp)])
        if c.returncode != 0:
            return False, None
        try:
            run = sh([str(binp)], timeout=RUN_TIMEOUT)
        except subprocess.TimeoutExpired:
            return True, None
        return True, run.stdout if run.returncode == 0 else None
    if lang == "node":
        chk = sh(["node", "--check", str(src)])
        if chk.returncode != 0:
            return False, None
        try:
            run = sh(["node", str(src)], timeout=RUN_TIMEOUT)
        except subprocess.TimeoutExpired:
            return True, None
        return True, run.stdout if run.returncode == 0 else None
    raise ValueError(lang)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("models", nargs="+", help="model dir name(s) under solutions/")
    ap.add_argument("--md", help="also write the scoreboard to this markdown file")
    args = ap.parse_args()

    tasks = json.loads((HERE / "tasks.json").read_text())["tasks"]
    expected = {t["name"]: t["expected"].strip() for t in tasks}

    lines: list[str] = []

    def emit(s: str = ""):
        lines.append(s)
        print(s)

    emit("# Generation-accuracy scoreboard")
    emit()
    emit("First-pass compile + correct-output rates for model-generated "
         "solutions to the matched tasks in `tasks.json`. Higher is better.")
    emit()

    for model in args.models:
        model_dir = HERE / "solutions" / model
        runs = sorted(model_dir.glob("run*"))
        if not runs:
            emit(f"_no solutions found under {model_dir.relative_to(HERE)}/_")
            continue
        emit(f"## `{model}`  ({len(runs)} run(s))")
        emit()
        # tallies[lang] = [compiled, correct, total]
        tally: dict[str, list[int]] = {}
        detail: list[str] = []
        for run in runs:
            for src in sorted(run.iterdir()):
                lang = EXT_LANG.get(src.suffix.lstrip("."))
                if lang is None:
                    continue
                name = src.stem
                if name not in expected:
                    continue
                compiled, out = build_and_run(lang, src, name)
                correct = compiled and out is not None and out.strip() == expected[name]
                t = tally.setdefault(lang, [0, 0, 0])
                t[0] += int(compiled)
                t[1] += int(bool(correct))
                t[2] += 1
                mark = "✓" if correct else ("~" if compiled else "✗")
                detail.append(f"  {mark} {model}/{run.name}/{name} [{lang}] "
                              f"compiled={compiled} correct={correct}")
        emit("| language | first-pass compile | correct output |")
        emit("|----------|-------------------:|---------------:|")
        for lang in ("nurl", "python", "rust", "node"):
            if lang not in tally:
                continue
            comp, corr, tot = tally[lang]
            emit(f"| {lang} | {comp}/{tot} ({100*comp//tot if tot else 0}%) "
                 f"| {corr}/{tot} ({100*corr//tot if tot else 0}%) |")
        emit()
        for d in detail:
            print(d)
        emit()

    if args.md:
        Path(args.md).write_text("\n".join(lines) + "\n")
        print(f"\nwrote {args.md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
