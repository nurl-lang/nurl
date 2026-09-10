#!/usr/bin/env python3
"""Trait declarations, impls and callers must agree under source reordering.

Run from any directory after ./build.sh. Positive cases go through the normal
NURL driver and must print 42; negative cases must name the actual violation.
The single-line cases are generated here because nurlfmt separates top-level
declarations: a formatted .nu fixture cannot preserve that regression.
"""
from concurrent.futures import ThreadPoolExecutor
import itertools
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

# Declarations are kept separate so every permutation denotes the same program.
POSITIVE = {
    "associated": (
        ": Number { i value }\n",
        ["% Reading [T] { type Elem @ read T self → Elem @ twice T self → Elem { ^ + ( read self ) ( read self ) } }",
         "% Reading Number { type Elem i @ read Number self → i { ^ . self value } }",
         "@ main → i { : Number x @ Number { 21 } ( nurl_println_int ( twice x ) ) ^ 0 }"],
    ),
    "inout": (
        ": Counter { i value }\n",
        ["% Increment [T] { @ add inout T self i amount → v @ increment inout T self → v { ( add self 1 ) } }",
         "% Increment Counter { @ add inout Counter self i amount → v { = . self value + . self value amount } }",
         "@ main → i { : ~ Counter x @ Counter { 41 } ( increment x ) ( nurl_println_int . x value ) ^ 0 }"],
    ),
    "dynamic_super": (
        ": Number { i value }\n",
        ["% Readable [T] { @ read T self → i }",
         "% Scored [T] : Readable { @ score T self → i { ^ * ( read self ) 2 } }",
         "% Readable Number { @ read Number self → i { ^ . self value } }",
         "% Scored Number { }",
         "@ main → i { : Number x @ Number { 14 } : %Scored obj ( dyn Scored x ) ( nurl_println_int + ( score obj ) ( read obj ) ) ^ 0 }"],
    ),
}
NEGATIVE = {
    "default_collision": (
        ["% First i { }", "% Second i { @ value i self → i { ^ self } }",
         "% First [T] { @ value T self → i { ^ 1 } }",
         "% Second [T] { @ value T self → i }"],
        "bare-name dispatch cannot disambiguate",
    ),
    "same_line_impl": (
        ["% Reading [T] { @ read T self → i }",
         "% Reading i { @ read i self → i { ^ 1 } }",
         "% Reading i { @ read i self → i { ^ 2 } }"],
        "duplicate impl of trait 'Reading'",
    ),
    "missing_binding": (
        ["% Reading i { }", "% Reading [T] { type Elem }"],
        "must bind associated type 'Elem'",
    ),
    "unknown_binding": (
        ["% Reading i { type Typo i }", "% Reading [T] { type Elem }"],
        "has no associated type 'Typo'",
    ),
}


def cases():
    for family, (prefix, declarations) in POSITIVE.items():
        for index, order in enumerate(itertools.permutations(declarations)):
            yield f"{family}_{index}", prefix + "\n".join(order) + "\n", None
    for family, (declarations, diagnostic) in NEGATIVE.items():
        for index, order in enumerate(itertools.permutations(declarations)):
            for layout, separator in [("lines", "\n"), ("one_line", " ")]:
                source = separator.join(order) + "\n@ main → i { ^ 0 }\n"
                yield f"{family}_{index}_{layout}", source, diagnostic


def check(work, case):
    name, source, diagnostic = case
    path = work / f"{name}.nu"
    path.write_text(source)
    try:
        if diagnostic:
            result = subprocess.run(
                [str(ROOT / "build/nurlc"), str(path)], cwd=ROOT,
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                text=True, timeout=15,
            )
            if result.returncode != 1 or diagnostic not in result.stderr:
                return f"{name}: wrong rejection (exit {result.returncode})\n{result.stderr}\n{source}"
        else:
            binary = work / name
            result = subprocess.run(
                [str(ROOT / "nurl.sh"), str(path), str(binary)], cwd=ROOT,
                env={**os.environ, "NURL_SPLIT": "0"},
                capture_output=True, text=True, timeout=60,
            )
            if result.returncode:
                return f"{name}: build failed\n{result.stdout}{result.stderr}\n{source}"
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=5)
            if result.returncode or result.stdout != "42\n":
                return f"{name}: wrong result {result.returncode}, {result.stdout!r}\n{result.stderr}\n{source}"
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"{name}: {error}\n{source}"
    return None


def main():
    if not (ROOT / "build/nurlc").is_file():
        raise SystemExit("build/nurlc missing — run ./build.sh first")
    roster = list(cases())
    with tempfile.TemporaryDirectory(prefix="nurl-trait-order-") as directory:
        with ThreadPoolExecutor(max_workers=4) as pool:
            failures = [failure for failure in pool.map(
                lambda case: check(Path(directory), case), roster
            ) if failure]
    for failure in failures:
        print(failure)
    print(f"trait-order: {len(roster) - len(failures)}/{len(roster)} cases passed "
          "(runtime results and diagnostic verdicts)")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
