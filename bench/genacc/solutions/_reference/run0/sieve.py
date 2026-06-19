#!/usr/bin/env python3
# sieve — Sieve of Eratosthenes, count primes ≤ 10_000_000.
import sys
N = 10_000_000
mark = bytearray(N)
mark[0] = 1
mark[1] = 1
p = 2
while p * p < N:
    if mark[p] == 0:
        m = p * p
        while m < N:
            mark[m] = 1
            m += p
    p += 1
count = 0
k = 2
while k < N:
    if mark[k] == 0:
        count += 1
    k += 1
print(count)
