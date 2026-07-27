#!/usr/bin/env python3
"""Compare two point clouds written by `ref_cloud.py` and `lingbot-map`.

  cmp_cloud.py <a.ply> <b.ply> [relative-tolerance]

Both are binary_little_endian PLY with the same property order. They are
NOT compared positionally: the confidence gate is a strict `>` against a
threshold, so a pixel whose confidence lands within f32 noise of it falls
on one side in one cloud and the other side in the other. A handful of
such pixels — a few per 30 000 — shifts every later point by one slot and
makes an index-wise diff meaningless while the reconstruction is in fact
identical.

So the question asked is the one that matters: does every point of A have
a point of B in the same place? That is a nearest-neighbour lookup, over
a sample, reported relative to the scene's own extent:

  * point counts, and how far apart they are in proportion
  * the median and 99th-percentile nearest-neighbour distance, A into B
  * centroid drift

A cloud that agrees to f32 noise gives a 99th percentile around 1e-6
relative. A cloud reconstructed slightly differently — a different scale
phase, a different window — gives something orders of magnitude larger,
and the point counts move too.
"""
import sys

import numpy as np
from scipy.spatial import cKDTree

SAMPLE = 200_000


def read_ply(path):
    with open(path, "rb") as f:
        hdr = b""
        while b"end_header" not in hdr:
            line = f.readline()
            if not line:
                sys.exit("%s: no end_header" % path)
            hdr += line
        txt = hdr.decode("ascii", "replace")
        if "format binary_little_endian" not in txt:
            sys.exit("%s: not binary_little_endian" % path)
        n = 0
        for line in txt.splitlines():
            if line.startswith("element vertex"):
                n = int(line.split()[2])
        dt = np.dtype([("x", "<f4"), ("y", "<f4"), ("z", "<f4"),
                       ("r", "u1"), ("g", "u1"), ("b", "u1")])
        d = np.frombuffer(f.read(n * dt.itemsize), dtype=dt, count=n)
    if len(d) != n:
        sys.exit("%s: header says %d vertices, body has %d" % (path, n, len(d)))
    return np.stack([d["x"], d["y"], d["z"]], 1).astype(np.float64)


def main():
    a_path, b_path = sys.argv[1], sys.argv[2]
    tol = float(sys.argv[3]) if len(sys.argv) > 3 else 1e-4
    A = read_ply(a_path)
    B = read_ply(b_path)
    if len(A) == 0 or len(B) == 0:
        sys.exit("one of the clouds is empty")

    count_drift = abs(len(A) - len(B)) / max(len(A), len(B))
    extent = float(np.linalg.norm(A.max(0) - A.min(0))) or 1.0

    rng = np.random.default_rng(0)
    idx = (rng.choice(len(A), SAMPLE, replace=False)
           if len(A) > SAMPLE else np.arange(len(A)))
    dist, _ = cKDTree(B).query(A[idx], k=1)
    med, p99, worst = (float(np.median(dist)), float(np.percentile(dist, 99)),
                       float(dist.max()))
    cdrift = float(np.linalg.norm(A.mean(0) - B.mean(0))) / extent

    print("points %d vs %d (%.4f%% apart)"
          % (len(A), len(B), 100 * count_drift))
    print("nearest-neighbour A->B over an extent of %.3f: "
          "median %.2e, p99 %.2e, worst %.2e (relative)"
          % (extent, med / extent, p99 / extent, worst / extent))
    print("centroid drift %.2e relative" % cdrift)

    # The MEDIAN is the verdict, not the tail. The p99 is dominated by
    # far-field points, where a relative depth difference of 1e-5 moves the
    # point a long way in absolute terms and says more about how far away
    # it is than about whether the two agree.
    ok = (med / extent) <= tol and count_drift <= 1e-3
    print("VERDICT", "match" if ok else "DIFFER")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
