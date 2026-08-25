#!/usr/bin/env python3
# tools/fuzz/reduce.py — shrink a failing generated program to the smallest
# one that still fails.
#
# A finding is only worth as much as its reproducer. A generated seed is
# 150–400 lines across a dozen unrelated features; the bug is usually two of
# them interacting, and finding out which two by hand costs more than the
# fix. This does that automatically: delete lines, keep whatever still
# reproduces, repeat with smaller chunks (classic ddmin over line
# granularity, plus a brace-repair pass so a half-deleted block does not just
# fail to parse and look like a hit).
#
# WHAT IS PRESERVED. The property being reduced against must survive line
# deletion, or the reducer converges on a different bug. Two of the four
# modes are oracle-free and always sound:
#
#   build   — the program does not compile (nurlc error, or clang rejecting
#             nurlc's IR). The largest finding class in practice.
#   crash   — it compiles but exits nonzero.
#   diverge — stdout at -O0 differs from stdout at -O2. Needs no oracle:
#             the two builds disagree with each other.
#   check   — the program is its OWN oracle (genprog.py --selfcheck embeds
#             each expected value as a string literal next to the expression
#             that produces it) and exits nonzero when one disagrees. This is
#             the mode that reduces a "wrong at every optimisation level"
#             miscompile, which the external-oracle form cannot: deleting a
#             line there desynchronises every later line of the oracle file.
#   sanitize — built with NURL_SAN=1 and run leak-detection-on; an
#             ASan/LSan/UBSan report or a nonzero exit is the property. For
#             the ownership-traffic findings, where stdout is right and the
#             bug is a leak or a double free.
#
# The `check` mode is why `--selfcheck` exists at all. Reduce a differential
# finding by regenerating the seed with `--selfcheck` first:
#
#   python3 tools/fuzz/genprog.py 684 --selfcheck > bug.nu
#   tools/fuzz/reduce.py bug.nu --mode check -o bug.min.nu
#
# fuzz.sh does exactly that for you on every finding.
#
# Usage:
#   reduce.py PROGRAM.nu [--mode build|crash|diverge|check] [-o OUT.nu]
#             [--opt -O0] [--timeout 40] [--quiet]
#
# Exit status: 0 if the reduced program still reproduces, 1 if the input did
# not reproduce in the first place (reported, never reduced silently).

import argparse
import re
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NURL = os.path.join(ROOT, "nurl.sh")


def _build(src_path, out_path, opt, timeout, san=False):
    """(ok, combined_output) for one nurl.sh compile."""
    env = dict(os.environ, NURL_STDLIB=os.environ.get("NURL_STDLIB", ROOT))
    if san:
        env["NURL_SAN"] = "1"
    try:
        r = subprocess.run([NURL, opt, src_path, out_path],
                           capture_output=True, text=True,
                           timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return False, "<compile timeout>"
    return r.returncode == 0, r.stdout + r.stderr


def _run(bin_path, timeout, san=False):
    """(returncode, stdout, stderr) for the compiled program; rc 124 on
    timeout. Leak detection is on for the sanitized property — a leak is a
    finding even when the program's output is right."""
    env = dict(os.environ)
    if san:
        env["ASAN_OPTIONS"] = "detect_leaks=1:exitcode=99"
    try:
        r = subprocess.run([bin_path], capture_output=True, text=True,
                           timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return 124, "", ""
    return r.returncode, r.stdout, r.stderr


def _err_sig(text, marker="error: "):
    """A stable fingerprint of a failure message: the first line carrying
    `marker`, with positions, quoted names and register numbers normalised
    away so the same bug in a smaller program still matches.

    Without this the reducer is worthless for build failures: "does not
    compile" is true of almost any mangled program, so ddmin happily deletes
    the binding a loop reads and reports a four-line file whose only problem
    is an undefined identifier."""
    for ln in text.splitlines():
        i = ln.find(marker)
        if i < 0:
            continue
        msg = ln[i + len(marker):].strip()
        msg = re.sub(r"%[A-Za-z_.]*\d+", "%REG", msg)
        msg = re.sub(r"'[^']*'", "'X'", msg)
        msg = re.sub(r"\d+", "N", msg)
        return msg[:160]
    return None


class Budget(Exception):
    """Raised when the test budget runs out — reduction stops with whatever
    it has. A reducer that runs unbounded is a reducer CI cannot call."""


class Property:
    """Does this source still exhibit the failure we are reducing?"""

    def __init__(self, mode, opt, timeout, budget=None):
        self.mode, self.opt, self.timeout = mode, opt, timeout
        self.budget = budget
        self.tests = 0
        # Fingerprint of the ORIGINAL failure, learned on the first call and
        # required of every candidate afterwards. Reducing against the bare
        # shape of the failure ("it does not compile", "it exits nonzero")
        # lets ddmin drift onto an unrelated breakage it introduced itself.
        self.sig = None
        self.sig_locked = False
        self.tmp = tempfile.mkdtemp(prefix="nurl-reduce-")

    def _same(self, sig):
        """First call defines the fingerprint; later calls must match it."""
        if not self.sig_locked:
            self.sig, self.sig_locked = sig, True
            return True
        return sig == self.sig

    def __call__(self, text):
        if self.budget is not None and self.tests >= self.budget:
            raise Budget()
        self.tests += 1
        return self._check(text)

    def _check(self, text):
        src = os.path.join(self.tmp, "p.nu")
        with open(src, "w") as f:
            f.write(text)
        if self.mode == "diverge":
            ok0, _ = _build(src, os.path.join(self.tmp, "a0"), "-O0", self.timeout)
            ok2, _ = _build(src, os.path.join(self.tmp, "a2"), "-O2", self.timeout)
            if not (ok0 and ok2):
                return False          # a build failure is a DIFFERENT bug
            rc0, out0, _ = _run(os.path.join(self.tmp, "a0"), self.timeout)
            rc2, out2, _ = _run(os.path.join(self.tmp, "a2"), self.timeout)
            return out0 != out2 or rc0 != rc2
        san = self.mode == "sanitize"
        ok, log = _build(src, os.path.join(self.tmp, "a"), self.opt,
                         self.timeout, san)
        if self.mode == "build":
            return (not ok) and self._same(_err_sig(log))
        if not ok:
            return False              # the other modes need it to compile
        rc, out, err = _run(os.path.join(self.tmp, "a"), self.timeout, san)
        if san:
            if rc == 0 and "ERROR:" not in err:
                return False
            return self._same(_err_sig(err, "ERROR: ") or f"rc={rc}")
        if rc == 0:
            return False
        if self.mode == "check":
            # Pin the specific expectation that disagreed, so the reducer
            # cannot swap one miscompiled value for another on the way down.
            want = None
            for ln in out.splitlines():
                if ln.startswith("MISMATCH "):
                    want = ln.split("want=")[-1].strip()
                    break
            return self._same(want or f"rc={rc}")
        return self._same(f"rc={rc}")


def _balanced(lines):
    """Reject a candidate whose braces no longer pair up. Without this the
    reducer happily deletes a `{` and calls the resulting parse error a hit,
    converging on a syntactically broken file instead of the bug."""
    depth = 0
    in_str = False
    for ln in lines:
        for ch in ln:
            if ch == "`":
                in_str = not in_str
            elif in_str:
                continue
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth < 0:
                    return False
    return depth == 0 and not in_str


def _units(lines):
    """Group lines into brace-balanced STATEMENTS.

    Deleting raw lines can never remove a multi-line construct — dropping the
    `: i m ?? e {` head leaves its arms and `}` behind, which does not parse,
    so the whole match survives every sweep. Grouping first means a five-line
    `??` block, a struct declaration or a loop body is one deletable item."""
    units, i, n = [], 0, len(lines)
    while i < n:
        j, depth = i, 0
        while j < n:
            for ch in lines[j]:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
            j += 1
            if depth <= 0:
                break
        units.append(lines[i:j])
        i = j
    return units


def _ddmin(items, join, prop, log, what):
    """Classic ddmin over a list: halve the chunk size down to one item.
    Returns (items, exhausted) — on budget exhaustion the progress made so
    far is kept, never discarded."""
    chunk = max(1, len(items) // 2)
    while chunk >= 1:
        i = 0
        while i < len(items):
            cand = items[:i] + items[i + chunk:]
            flat = join(cand)
            try:
                hit = bool(flat) and _balanced(flat) and prop("\n".join(flat))
            except Budget:
                return items, True
            if hit:
                items = cand
                log(f"  -{chunk} {what} at {i} → {len(join(items))} lines")
            else:
                i += chunk
        chunk //= 2
    return items, False


def reduce_lines(lines, prop, log):
    """Statement-granular ddmin, then line-granular, repeated until a whole
    sweep changes nothing — one removal routinely unblocks another (dropping
    the last use of a binding is what lets the binding itself go)."""
    while True:
        before = len(lines)
        units, out = _ddmin(_units(lines), lambda us: [l for u in us for l in u],
                            prop, log, "stmt(s)")
        lines = [l for u in units for l in u]
        if not out:
            lines, out = _ddmin(lines, lambda ls: ls, prop, log, "line(s)")
        if out:
            log(f"  budget exhausted after {prop.tests} tests — "
                f"stopping at {len(lines)} lines")
            return lines
        if len(lines) == before:
            return lines


def main():
    ap = argparse.ArgumentParser(description="shrink a failing NURL program")
    ap.add_argument("program")
    ap.add_argument("--mode", default="build",
                    choices=["build", "crash", "diverge", "check", "sanitize"])
    ap.add_argument("-o", "--out", default=None,
                    help="output path (default: PROGRAM with .min.nu)")
    ap.add_argument("--opt", default="-O0", help="opt level for build/crash/check")
    ap.add_argument("--timeout", type=int, default=40)
    ap.add_argument("--max-tests", type=int, default=400,
                    help="compile+run budget; 0 = unbounded (default 400)")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    def log(msg):
        if not a.quiet:
            print(msg, file=sys.stderr)

    text = open(a.program).read()
    lines = text.rstrip("\n").split("\n")
    prop = Property(a.mode, a.opt, a.timeout,
                   a.max_tests if a.max_tests > 0 else None)

    if not prop(text):
        print(f"reduce.py: {a.program} does not reproduce under --mode "
              f"{a.mode} — nothing to reduce (wrong mode, or the bug is "
              f"already fixed).", file=sys.stderr)
        return 1

    log(f"reduce.py: {len(lines)} lines, mode={a.mode}")
    lines = reduce_lines(lines, prop, log)
    out = a.out or (a.program[:-3] if a.program.endswith(".nu") else a.program) + ".min.nu"
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    log(f"reduce.py: {len(lines)} lines → {out}")
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
