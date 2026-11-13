# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Run the core-IR checker over hole probes and compare with each probe's
`// map:` verdict (rejected / runs-clean).

  python tools/ncore/run.py [--nurlc] [--all] [--clean] [--list FILE] [--jobs N] [--show N] [probe.nu ...]

--nurlc checks the IR nurlc itself lowers the program to (fromnurlc.py);
without it the prototype's own parser and lowering are used. --clean takes
every file given as a program that must be accepted (the tree's own code:
a refusal there is a rule written too coarsely).
"""
import os
import sys
import collections
import traceback

sys.setrecursionlimit(10000)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from syntax import Unsupported, ParseError       # noqa: E402
from load import load, lib_headers               # noqa: E402
from lower import build_program                  # noqa: E402
from check import check_program, CheckError      # noqa: E402
import fromnurlc                                 # noqa: E402
import derive                                    # noqa: E402

HOLES = os.path.join(HERE, "..", "fuzz", "holes")


CLEAN = False     # --clean: every file given is a program that must be accepted


def expected(path):
    if CLEAN:
        return "runs-clean"
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("// map:"):
                cols = [c.strip() for c in line[len("// map:"):].split("|")]
                return cols[2] if len(cols) > 2 else None
    return None


def verdict(path):
    decls, imports = load(path)
    hdrs = dict(lib_headers())
    hdrs["mem_dup"] = (["T"], [("in", ("tvar", "T"), "x")], ("tvar", "T"))
    prog = build_program(decls, hdrs)
    errors, summ = check_program(prog)
    return ("rejected" if errors else "runs-clean"), errors, summ


# What marks a diagnostic of the fused walk that the ownership engine does
# not replace (docs/spec.md §3.3d, MEMORY.md §6.5's Send / Sync, typing).
WALK_RULES = ("raw memory", "only an 'unsafe' function", "which only an 'unsafe'", "is not Send", "is not Sync",
              "not Send:", "is set at start", "is declared 'raw'", "runtime handle", "FFI parameter",
              "expects type", "undefined identifier", "internal to the standard library",
              "takes a raw pointer", "hands back a raw pointer", "the standard library's address",
              "a number passed where", "is left out of this literal", "carries a payload, and a bare variant",
              "was bound inside the value block", "fills its value with zero bytes", "cannot assign to immutable",
              "and every thread can", "a number cannot become", "passes a C stream", "would copy a '",
              "where several threads may run", "asserts that '")


def verdict_nurlc(path):
    """The verdict on the IR nurlc itself lowers the program to.

    The program's own functions are checked.  A function of the standard
    library is trusted: a declared summary (prims.py) answers for it; one
    with none whose body uses no raw memory is walked for its summary, and
    one that does needs a declared summary."""
    from prims import PRIMS
    rd, gaps, rc, err = fromnurlc.read_program(path)
    if rc != 0:
        first = next((l for l in err.splitlines() if "error" in l), "nurlc failed")
        msg = first.split("error:")[-1].strip()
        # A refusal that is no ownership rule - the raw-memory boundary, a
        # type that may not cross to another thread, a type error - is the
        # walk's to make, on types alone: the engine is not asked.
        if any(w in msg for w in WALK_RULES):
            return "rejected", [("nurlc", 0, "the walk: " + msg[:60])], {}
        raise Unsupported("nurlc: " + msg[:40])
    prog = rd.prog
    every = dict(prog.fns)

    memo = {}

    def derived(n):
        """The summary of library function `n` the walk's answers give
        (derive.py); None for one the walk did not compile."""
        if n not in memo:
            fn = every.get(n)
            if fn is None:
                # a function of the runtime, an extern: no body anywhere
                memo[n] = derive.extern(prog.walk_sums[n]) if n in prog.walk_sums else None
            else:
                ws = derive.walk_answers(prog, n) if prog.fn_flags[n] & 1 else {}
                memo[n] = derive.derive(prog, fn, ws) if ws.get("body_done") else None
        return memo[n]
    prog.derived = derived

    def declared(n):
        return (PRIMS.get(n) is not None or PRIMS.get(prog.fn_tmpl.get(n) or "") is not None
                or derived(n) is not None)

    def callees(fn):
        out = set()
        for line in fn.raw["stmts"]:
            t = line.split(" ")
            for i, w in enumerate(t[:-1]):
                if w in ("call", "closure") and i <= 2:
                    out.add(t[i + 1])
        return out

    todo = [(n, None) for n, f in every.items() if not prog.fn_flags[n] & 1]
    keep = {}
    trusted = set()
    while todo:
        n, by = todo.pop()
        if n in keep or n not in every:
            continue
        flags = prog.fn_flags[n]
        if flags & 1:
            if declared(n):
                continue
            if flags & 2:
                # the library function the program called that led here is
                # the one to declare a summary for
                top = by or n
                raise Unsupported(f"no summary for {prog.fn_tmpl.get(top) or top}")
            trusted.add(n)
        keep[n] = every[n]
        # (`src`: the library function the program itself called on the way here)
        src = (by or n) if flags & 1 else None
        for c in callees(every[n]):
            todo.append((c, src))
            todo.extend((m, src) for m in prog.virt.get(c, ()))
    for n, fn in list(keep.items()):
        try:
            rd.lower_body(fn)
        except Unsupported:
            # a library function that reads a handle's own fields has no
            # body the checker follows: the walk's answers stand for it
            if not prog.fn_flags[n] & 1 or derived(n) is None:
                raise
            del keep[n]
            trusted.discard(n)
    prog.fns = keep
    prog.trusted = trusted
    errors, summ = check_program(prog)
    return ("rejected" if errors else "runs-clean"), errors, summ


def one(job):
    """One probe's outcome: (name, status, detail, first error)."""
    path, use_nurlc = job
    exp = expected(path)
    name = os.path.basename(path)
    try:
        got, errors, _ = (verdict_nurlc if use_nurlc else verdict)(path)
    except Unsupported as e:
        return (name, "skip", str(e)[:80], None)
    except RecursionError:
        return (name, "crash", "RecursionError", None)
    except (ParseError, CheckError, KeyError, IndexError, TypeError, AttributeError, ValueError) as e:
        return (name, "crash", type(e).__name__ + ": " + str(e)[:80], None)
    st = "agree" if exp == got else "false-accept" if exp == "rejected" else "false-reject"
    return (name, st, got, errors[0] if errors else None)


def main(argv):
    files = []
    show = 15
    use_nurlc = False
    jobs = 0
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--list":
            with open(argv[i + 1]) as f:
                files += [os.path.join(HOLES, l.strip()) for l in f if l.strip()]
            i += 2
            continue
        if a == "--nurlc":
            use_nurlc = True
            i += 1
            continue
        if a == "--clean":
            global CLEAN
            CLEAN = True
            i += 1
            continue
        if a == "--all":
            files += sorted(os.path.join(HOLES, n) for n in os.listdir(HOLES) if n.endswith(".nu"))
            i += 1
            continue
        if a == "--jobs":
            jobs = int(argv[i + 1])
            i += 2
            continue
        if a == "--show":
            show = int(argv[i + 1])
            i += 2
            continue
        files.append(a if os.path.exists(a) else os.path.join(HOLES, a))
        i += 1
    work = [(p, use_nurlc) for p in files]
    if jobs > 1 and len(files) > 3:
        import multiprocessing
        with multiprocessing.Pool(jobs) as pool:
            done = pool.map(one, work, chunksize=8)
    else:
        done = [one(w) for w in work]
    counts = collections.Counter()
    skips = collections.Counter()
    mism = {"false_accept": [], "false_reject": []}
    for name, st, detail, err in done:
        if st == "skip":
            counts["skip"] += 1
            skips[detail.split(" (")[0][:40]] += 1
        elif st == "crash":
            counts["crash"] += 1
            skips["CRASH " + detail[:60]] += 1
        elif st == "agree":
            counts["agree:" + detail] += 1
        elif st == "false-accept":
            counts["FALSE-ACCEPT"] += 1
            mism["false_accept"].append(name)
        else:
            counts["false-reject"] += 1
            mism["false_reject"].append((name, err))
        if len(files) <= 3:
            print(name, "expected", expected(os.path.join(HOLES, name)) if os.path.exists(os.path.join(HOLES, name)) else None,
                  "got", detail)
            if err:
                print("   ", err)
    print(dict(counts))
    print("skips:", skips.most_common(25))
    print("FALSE ACCEPTS (unsafe, the checker accepts):", len(mism["false_accept"]))
    for n in mism["false_accept"][:show]:
        print("   ", n)
    print("false rejects (safe, the checker refuses):", len(mism["false_reject"]))
    for n, e in mism["false_reject"][:show]:
        print("   ", n, "--", e)
    if len(files) > 3:
        out = "results_clean.tsv" if CLEAN else "results_nurlc.tsv" if use_nurlc else "results_own.tsv"
        with open(os.path.join(HERE, out), "w", encoding="utf-8") as f:
            f.write("".join(f"{n}\t{st}\t{err if err else detail}\n" for n, st, detail, err in done))


if __name__ == "__main__":
    main(sys.argv[1:])
