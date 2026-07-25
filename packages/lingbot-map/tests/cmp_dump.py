#!/usr/bin/env python3
"""Compare "<label> <shape> | <values…>" dumps: the reference produced by
tests/agg_oracle.py against what the port produced. Shapes must match
exactly; values to a relative tolerance, because the port computes in
float32 on purpose."""
import sys

ref_path, got_path, tol = sys.argv[1], sys.argv[2], float(sys.argv[3])
ref = {l.split()[0]: l for l in open(ref_path) if l.strip() and "|" in l}
worst_all, n = 0.0, 0
for line in open(got_path):
    if not line.strip() or "|" not in line:
        continue
    key = line.split()[0]
    if key not in ref:
        print("no reference row for %s" % key)
        sys.exit(1)
    rh, rv = ref[key].split("|")
    gh, gv = line.split("|")
    if rh.split()[1] != gh.split()[1]:
        print("%s shape %s vs %s" % (key, rh.split()[1], gh.split()[1]))
        sys.exit(1)
    r = [float(x) for x in rv.split()]
    g = [float(x) for x in gv.split()]
    if len(r) != len(g):
        print("%s sample count %d vs %d" % (key, len(r), len(g)))
        sys.exit(1)
    w = max((abs(a - b) / max(1.0, abs(a)) for a, b in zip(r, g)), default=0.0)
    worst_all = max(worst_all, w)
    n += 1
if n == 0:
    print("nothing compared")
    sys.exit(1)
if worst_all > tol:
    print("worst relative error %.3e > %.0e over %d rows" % (worst_all, tol, n))
    sys.exit(1)
print("%d row(s), worst relative error %.3e" % (n, worst_all))
