#!/usr/bin/env python3
# quicksort — sort 5000 LCG ints in place, print a position-weighted checksum.
import sys

sys.setrecursionlimit(20000)


def qsort(a, lo, hi):
    if lo >= hi:
        return
    pivot = a[hi]
    st = lo
    for j in range(lo, hi):
        if a[j] < pivot:
            a[st], a[j] = a[j], a[st]
            st += 1
    a[st], a[hi] = a[hi], a[st]
    qsort(a, lo, st - 1)
    qsort(a, st + 1, hi)


N = 5000
a = [0] * N
x = 1
for i in range(N):
    x = (x * 1103515245 + 12345) % 1048576
    a[i] = x

qsort(a, 0, N - 1)
total = 0
for k in range(N):
    total += (k + 1) * a[k]
print(total)
