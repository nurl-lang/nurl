#!/usr/bin/env python3
# benchmark-contract: prefix-scan;seed=123456789;batches=1000000;width=16;value-mask=65535
#
# prefix_scan — 1M batches of "fill 16 slots from the LCG, then run an
# in-place running sum over them". A store-bound fill followed by a
# serial dependency chain of loads and adds.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
values = [0] * 16
state = 123456789
checksum = 0

for _ in range(1_000_000):
    for index in range(16):
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        values[index] = state & 0xFFFF
    for index in range(1, 16):
        values[index] += values[index - 1]
    checksum ^= values[15]

print((state ^ checksum) & 0x7FFFFFFFFFFFFFFF)
