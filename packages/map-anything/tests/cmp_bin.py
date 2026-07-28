#!/usr/bin/env python3
"""Compare two flat f32 binaries: max abs diff, max rel diff, and the
worst element's index. Exit 1 if max abs diff exceeds the gate.

Usage: cmp_bin.py a.bin b.bin [gate]   (default gate 1e-4)
"""

import sys

import numpy as np


def main():
    a = np.fromfile(sys.argv[1], dtype=np.float32).astype(np.float64)
    b = np.fromfile(sys.argv[2], dtype=np.float32).astype(np.float64)
    gate = float(sys.argv[3]) if len(sys.argv) > 3 else 1e-4
    assert a.shape == b.shape, (a.shape, b.shape)
    d = np.abs(a - b)
    i = int(d.argmax())
    denom = np.maximum(np.abs(a), 1e-6)
    rel = (d / denom).max()
    print(
        "n=%d max_abs=%.3g (at %d: %.6g vs %.6g) max_rel=%.3g mean_abs=%.3g"
        % (a.size, d.max(), i, a[i], b[i], rel, d.mean())
    )
    sys.exit(0 if d.max() <= gate else 1)


if __name__ == "__main__":
    main()
