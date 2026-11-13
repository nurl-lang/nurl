# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Run the core-IR checker over hole probes and compare with each probe's
`// map:` verdict (rejected / runs-clean).

  python tools/ncore/run.py [--list FILE] [--show N] [probe.nu ...]
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

HOLES = os.path.join(HERE, "..", "fuzz", "holes")


def expected(path):
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
        raise Unsupported("nurlc: " + first.split("error:")[-1].strip()[:40])
    prog = rd.prog
    every = dict(prog.fns)

    def declared(n):
        return PRIMS.get(n) is not None or PRIMS.get(prog.fn_tmpl.get(n) or "") is not None

    def callees(fn):
        out = set()
        for line in fn.raw["stmts"]:
            t = line.split(" ")
            for i, w in enumerate(t[:-1]):
                if w in ("call", "closure") and i <= 2:
                    out.add(t[i + 1])
        return out

    todo = [n for n, f in every.items() if not prog.fn_flags[n] & 1]
    keep = {}
    trusted = set()
    while todo:
        n = todo.pop()
        if n in keep or n not in every:
            continue
        flags = prog.fn_flags[n]
        if flags & 1:
            if declared(n):
                continue
            if flags & 2:
                raise Unsupported(f"no summary for {prog.fn_tmpl.get(n) or n}")
            trusted.add(n)
        keep[n] = every[n]
        todo.extend(callees(every[n]))
    for fn in keep.values():
        rd.lower_body(fn)
    prog.fns = keep
    prog.trusted = trusted
    errors, summ = check_program(prog)
    return ("rejected" if errors else "runs-clean"), errors, summ


def main(argv):
    files = []
    show = 15
    use_nurlc = False
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
        if a == "--show":
            show = int(argv[i + 1])
            i += 2
            continue
        files.append(a if os.path.exists(a) else os.path.join(HOLES, a))
        i += 1
    counts = collections.Counter()
    results = []
    skips = collections.Counter()
    mism = {"false_accept": [], "false_reject": []}
    for path in files:
        exp = expected(path)
        name = os.path.basename(path)
        try:
            got, errors, _ = (verdict_nurlc if use_nurlc else verdict)(path)
        except Unsupported as e:
            counts["skip"] += 1
            skips[str(e).split(" (")[0][:40]] += 1
            results.append((name, "skip", str(e)[:80]))
            continue
        except (ParseError, CheckError, KeyError, IndexError, TypeError, AttributeError, ValueError) as e:
            counts["crash"] += 1
            skips["CRASH " + type(e).__name__ + ": " + str(e)[:60]] += 1
            results.append((name, "crash", type(e).__name__ + ": " + str(e)[:80]))
            if len(argv) <= 3:
                traceback.print_exc()
            continue
        results.append((name, "agree" if exp == got else "false-accept" if exp == "rejected" else "false-reject",
                        str(errors[0]) if errors else ""))
        if exp == got:
            counts["agree:" + got] += 1
        elif exp == "rejected":
            counts["FALSE-ACCEPT"] += 1
            mism["false_accept"].append(name)
        else:
            counts["false-reject"] += 1
            mism["false_reject"].append((name, errors[0] if errors else None))
        if len(files) <= 3:
            print(name, "expected", exp, "got", got)
            for e in errors:
                print("   ", e)
    print(dict(counts))
    print("skips:", skips.most_common(25))
    print("FALSE ACCEPTS (unsafe, prototype accepts):", len(mism["false_accept"]))
    for n in mism["false_accept"][:show]:
        print("   ", n)
    print("false rejects (safe, prototype refuses):", len(mism["false_reject"]))
    for n, e in mism["false_reject"][:show]:
        print("   ", n, "--", e)
    with open(os.path.join(HERE, "results_nurlc.tsv" if use_nurlc else "results_own.tsv"), "w", encoding="utf-8") as f:
        f.write("".join(f"{n}\t{st}\t{why}\n" for n, st, why in results))
    with open(os.path.join(HERE, "last_run_nurlc.txt" if use_nurlc else "last_run.txt"), "w", encoding="utf-8") as f:
        f.write("FALSE_ACCEPT\n" + "\n".join(mism["false_accept"]) + "\nFALSE_REJECT\n")
        f.write("\n".join(f"{n}\t{e}" for n, e in mism["false_reject"]) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
