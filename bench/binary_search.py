#!/usr/bin/env python3
# benchmark-contract: binary-search;seed=123456789;queries=5000000;values=even-0..126;algorithm=lower-bound
#
# binary_search — 5M lower-bound searches over a 64-entry sorted table
# of the even numbers 0..126, with LCG-drawn targets in 0..127 so about
# half the queries hit. Six dependent, unpredictable steps per query.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
values = [2 * i for i in range(64)]

state = 123456789
hits = 0

for _ in range(5_000_000):
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    target = state & 127

    low = 0
    high = 64
    while low < high:
        middle = low + ((high - low) >> 1)
        if values[middle] < target:
            low = middle + 1
        else:
            high = middle

    if low < 64 and values[low] == target:
        hits += 1

print((state ^ hits) & 0x7FFFFFFFFFFFFFFF)
