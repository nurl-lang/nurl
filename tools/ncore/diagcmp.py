# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""The engine's diagnostics against the walk's goldens: the same place?

Every compiler test whose golden (compiler/tests/outputs/<name>.txt) is a
refusal (`COMPILE FAIL`) names where the walk refuses: its first
`file:line:col: error:` line (a `should_fail_*` golden records none, so
the line comes from running the compiler as the test runner does). The
same file is compiled with the walk's ownership refusals left to the
engine, which then reports what it finds:

  nurlc --emit-core --engine-decides <file>   `--emit-core` silences the
        walk's ownership refusals (g_walk_owns 0), `--engine-decides` has
        the engine print its findings as full source diagnostics on stderr
        (`file:line:col: error:` and the rule group's `note:` / `help:`)
        and no IR text (alone, `--engine-decides` leaves the walk speaking,
        and its refusals stop the compile first)
  nurlc --engine <file>                       the same walk; the engine's
        `eng verdict` line tells a module it cannot read (`skip`) from one
        it reads and finds nothing in (`runs-clean`)

and each test is put in one class:

  SAME-LINE       the engine's first finding is on the golden's file and line
  OTHER-LINE      the engine refuses, its first finding elsewhere
  ENGINE-ACCEPTS  the engine reads the module and finds nothing
  ENGINE-SKIP     the engine does not read the module (`eng verdict skip`)
  WALK-KEEPS      the walk-silent compile still stops on the golden's line,
                  with a refusal of the walk's own: no ownership rule (typing,
                  syntax, the raw boundary), or one the walk makes whatever
                  g_walk_owns says (Send/Sync, a closure's or a return's
                  keeps, a stale pointer): the engine is not reached
  ENGINE-CRASH    the engine stops with an internal error (on any test)
  OTHER-STOP      the walk-silent compile stops on another line with an error
                  that is not the engine's, before the engine runs (or times out),
                  or the `--engine` run gives no clean verdict
  ENGINE-ONLY     the golden accepts, the engine refuses (every accepted
                  golden is compiled once, walk-silent)

"First" is the first printed (the walk and the engine each print in
their own order, not by line). For a refusal the engine makes: whether
some finding of it is on the golden's first line at all, whether the two
sets of lines (in the test's own file) are the same, and whether its
message (the one on the golden's line, else its first) names, quoted,
the binding the golden's first message names: `y` its first quoted name
(`'h.cb'` is `h`'s), `a` another quoted name of it, `n` none of them.

  PYTHONUTF8=1 python diagcmp.py --jobs 8                  every test
  PYTHONUTF8=1 python diagcmp.py --list names.txt --tsv out.tsv
  PYTHONUTF8=1 python diagcmp.py borrow_foo diag_bar.nu    some tests

A test is named by its name or its .nu path. `--tsv OUT` writes one line
per test (name, class, the golden's place and message, the engine's place
and message, a finding on the golden's line, the binding, both sets of
lines, where the golden's place came from: `golden` or `run`). `--top N` the rule groups shown per class (default 5).
(NURLC=<binary>.) Nothing is written but OUT. Exit status 1 if any test
is not SAME-LINE / WALK-KEEPS, or a test named has no golden (the others
are still compared).

The baseline (2026-11-20, main 72499862, before AGORA-877 (c)): of 814
refusal goldens, 212 same line, 27 other line, 27 engine accepts, 0 engine
skips, 546 the walk's own, 2 engine crashes; 2 more crashes and 1
engine-only among the accepted goldens. Of the 239 the engine refuses,
220 have a finding on the golden's line and 201 the same set of lines;
the binding named 158 of 224 (another name of it 23).
"""

import os
import re
import subprocess
import sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor

ROOT = os.environ.get("NCORE_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TESTS = os.path.join("compiler", "tests")
DIAG = re.compile(r"^(.+?):(\d+):(\d+): error: (.*)$")
QUOTED = re.compile(r"'([A-Za-z_][A-Za-z0-9_.]*)'")
CLASSES = ("SAME-LINE", "OTHER-LINE", "ENGINE-ACCEPTS", "ENGINE-SKIP", "WALK-KEEPS", "ENGINE-CRASH", "OTHER-STOP",
           "ENGINE-ONLY")
CRASH = "internal error in the ownership engine"


def flag_of(name):
    """The flag the test runner adds for a test (test_harness.sh's test_compiler_flag)."""
    for prefix, flag in (("borrow_strict_", "--strict-borrowck"), ("nobck_", "--no-borrowck"),
                         ("lint_", "--lint"), ("arity_strict_", "--strict-arity")):
        if name.startswith(prefix):
            return [flag]
    return []


def nurlc(args, name):
    exe = os.environ.get("NURLC") or os.path.join(ROOT, "build", "nurlc")
    src = os.path.join(TESTS, name + ".nu")
    try:
        r = subprocess.run([exe] + args + flag_of(name) + [src], cwd=ROOT, capture_output=True,
                           text=True, encoding="utf-8", errors="replace", timeout=300)
    except subprocess.TimeoutExpired:
        return None, "", ""
    return r.returncode, r.stdout, r.stderr


def diags(text):
    """The `file:line:col: error:` lines of a compile, each with whether it
    is the engine's (eng_report follows it with a `note:` naming docs/MEMORY.md)."""
    lines = text.split("\n")
    out = []
    for i, ln in enumerate(lines):
        m = DIAG.match(ln)
        if m:
            eng = any(x.startswith("  note: ") and "(docs/MEMORY.md §" in x for x in lines[i + 1:i + 5]
                      if not DIAG.match(x))
            out.append((m.group(1), int(m.group(2)), m.group(4), eng))
    return out


def golden(name):
    """('reject'|'accept'|None, its errors [(file, line, msg, False)])."""
    path = os.path.join(ROOT, TESTS, "outputs", name + ".txt")
    if not os.path.exists(path):
        return None, []
    text = open(path, encoding="utf-8", errors="replace").read()
    if not text.startswith("COMPILE FAIL"):
        return "accept", []
    return "reject", diags(text)


def lines_in(found, name):
    own = os.path.join(TESTS, name + ".nu")
    return sorted({d[1] for d in found if d[0] == own})


def roots(msg):
    """The quoted names of a message, each as its binding (`'h.cb'` is `h`)."""
    return [q.split(".")[0] for q in QUOTED.findall(msg)]


def same_binding(gold_msg, eng_msg):
    names, theirs = roots(gold_msg), set(roots(eng_msg))
    if not names:
        return "-"
    return "y" if names[0] in theirs else ("a" if theirs.intersection(names) else "n")


def rule_key(msg):
    """A message as its rule: names, numbers and what follows the first dash left out."""
    msg = msg.split(" — ")[0].split(" -- ")[0]
    msg = re.sub(r"'[^']*'", "'_'", msg)
    msg = re.sub(r"\b\d+\b", "N", msg)
    return " ".join(msg.split()[:12])


def classify(name):
    kind, gfound = golden(name)
    if kind is None:
        return None
    src = "golden"
    if kind == "reject" and not gfound:
        rc, _, err = nurlc(["--check"], name)
        gfound = diags(err)
        src = "run"
    gold = gfound[0][:3] if gfound else None
    rc, _, err = nurlc(["--emit-core", "--engine-decides"], name)
    found = diags(err)
    engf = [d for d in found if d[3]]
    row = {"name": name, "kind": kind, "src": src, "gold": gold, "eng": None, "same_binding": "-", "on_line": "-",
           "glines": lines_in(gfound, name), "elines": lines_in(engf, name)}
    if rc is None:
        row["class"], row["eng"] = "OTHER-STOP", ("timeout", 0, "", False)
        return row
    if CRASH in err:
        row["class"], row["eng"] = "ENGINE-CRASH", ("nurlc", 0, next(ln for ln in err.split("\n") if CRASH in ln), False)
        return row
    if kind == "accept":
        if not engf:
            return None                          # (a compile that fails here wants what the runner gives it: a link, a host)
        row["class"], row["eng"] = "ENGINE-ONLY", engf[0]
        return row
    if engf:
        on_line = [d for d in engf if gold and d[0] == gold[0] and d[1] == gold[1]]
        row["class"] = "SAME-LINE" if gold and engf[0][:2] == gold[:2] else "OTHER-LINE"
        row["on_line"] = "y" if on_line else "n"
        row["eng"] = (on_line or engf)[0]
        if gold:
            row["same_binding"] = same_binding(gold[2], row["eng"][2])
        return row
    if rc != 0:
        first = found[0] if found else None
        if first and gold and first[:2] == gold[:2]:
            row["class"], row["eng"] = "WALK-KEEPS", first
        else:
            row["class"] = "OTHER-STOP"
            last = [ln for ln in err.split("\n") if "error" in ln]
            row["eng"] = first or ("nurlc", 0, (last[0] if last else f"rc={rc}")[:160], False)
        return row
    rc, out, err = nurlc(["--engine"], name)
    if rc is None:
        row["class"], row["eng"] = "OTHER-STOP", ("timeout", 0, "--engine", False)
        return row
    if CRASH in err:
        row["class"], row["eng"] = "ENGINE-CRASH", ("nurlc", 0, next(ln for ln in err.split("\n") if CRASH in ln), False)
        return row
    verdict = next((ln.split("\t")[2:] for ln in out.split("\n") if ln.startswith("eng\tverdict\t")), ["none"])
    if verdict[0] == "skip":
        row["class"], row["eng"] = "ENGINE-SKIP", ("skip", 0, " ".join(verdict[1:]), False)
    elif verdict[0] == "runs-clean" and rc == 0:
        row["class"] = "ENGINE-ACCEPTS"
    else:
        # (no clean verdict: the shadow run stopped, or says otherwise)
        last = [ln for ln in err.split("\n") if "error" in ln]
        row["class"] = "OTHER-STOP"
        row["eng"] = ("nurlc", 0, (last[0] if last else f"--engine: rc={rc}, verdict {' '.join(verdict)}")[:160], False)
    return row


def names_of(args):
    out = []
    for a in args:
        out.append(os.path.splitext(os.path.basename(a))[0])
    return out


def loc(d):
    return f"{d[0]}:{d[1]}" if d else "-"


def main(argv):
    jobs, tsv, top = 1, None, 5
    picked = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--jobs":
            jobs = int(argv[i + 1]); i += 2
        elif a == "--tsv":
            tsv = argv[i + 1]; i += 2
        elif a == "--top":
            top = int(argv[i + 1]); i += 2
        elif a == "--list":
            picked += [ln.strip() for ln in open(argv[i + 1], encoding="utf-8") if ln.strip()]; i += 2
        elif a in ("-h", "--help"):
            print(__doc__)
            return 2
        else:
            picked.append(a); i += 1
    missing = []
    if picked:
        names = names_of(picked)
        missing = [n for n in names if not os.path.exists(os.path.join(ROOT, TESTS, "outputs", n + ".txt"))]
        for n in missing:
            print(f"diagcmp: {n}: no golden in {TESTS}/outputs", file=sys.stderr)
    else:
        names = sorted(f[:-3] for f in os.listdir(os.path.join(ROOT, TESTS)) if f.endswith(".nu"))
    rows = []
    with ProcessPoolExecutor(max_workers=jobs) as ex:
        for row in ex.map(classify, names, chunksize=4):
            if row is not None:
                rows.append(row)
    count = Counter(r["class"] for r in rows)
    if tsv:
        with open(tsv, "w", encoding="utf-8") as o:
            o.write("test\tclass\tgolden\tgolden_msg\tengine\tengine_msg\ton_golden_line\tsame_binding"
                    "\tgolden_lines\tengine_lines\tgolden_from\n")
            for r in rows:
                g, e = r["gold"], r["eng"]
                o.write("\t".join([r["name"], r["class"], loc(g), g[2] if g else "-", loc(e) if e and e[1] else
                                   (e[0] if e else "-"), e[2] if e else "-", r["on_line"], r["same_binding"],
                                   ",".join(map(str, r["glines"])) or "-", ",".join(map(str, r["elines"])) or "-",
                                   r["src"]]) + "\n")
    for cls in ("OTHER-LINE", "ENGINE-ACCEPTS", "ENGINE-SKIP", "ENGINE-CRASH", "OTHER-STOP", "ENGINE-ONLY", "WALK-KEEPS"):
        sel = [r for r in rows if r["class"] == cls]
        if not sel:
            continue
        key = (lambda r: rule_key(r["eng"][2])) if cls in ("ENGINE-ONLY", "ENGINE-SKIP", "OTHER-STOP") \
            else (lambda r: rule_key(r["gold"][2]) if r["gold"] else "(the golden accepts)")
        groups = Counter(key(r) for r in sel)
        print(f"{cls} ({len(sel)}):")
        for k, n in groups.most_common(top):
            ex1 = next(r["name"] for r in sel if key(r) == k)
            print(f"  {n:4d}  {k}   (e.g. {ex1})")
    found = [r for r in rows if r["class"] in ("SAME-LINE", "OTHER-LINE")]
    on_line = sum(1 for r in found if r["on_line"] == "y")
    same_set = sum(1 for r in found if r["glines"] == r["elines"])
    named = [r for r in rows if r["same_binding"] != "-"]
    same_b = sum(1 for r in named if r["same_binding"] == "y")
    other_b = sum(1 for r in named if r["same_binding"] == "a")
    refused = sum(1 for r in rows if r["kind"] == "reject")
    print(f"diagcmp: {refused} refusals: {count['SAME-LINE']} same line, {count['OTHER-LINE']} other line, "
          f"{count['ENGINE-ACCEPTS']} engine accepts, {count['ENGINE-SKIP']} engine skips, "
          f"{count['WALK-KEEPS']} the walk's own, {count['ENGINE-CRASH']} engine crashes "
          f"({sum(1 for r in rows if r['class'] == 'ENGINE-CRASH' and r['kind'] == 'accept')} on accepted tests), "
          f"{count['OTHER-STOP']} other stops; {count['ENGINE-ONLY']} engine-only; of the {len(found)} the engine "
          f"refuses: {on_line} with a finding on the golden's line, {same_set} on the same lines, "
          f"the binding named {same_b} of {len(named)} (another name of it {other_b})")
    return 1 if missing or sum(count[c] for c in CLASSES if c not in ("SAME-LINE", "WALK-KEEPS")) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
