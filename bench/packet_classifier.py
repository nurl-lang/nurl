#!/usr/bin/env python3
# benchmark-contract: branch-lcg32;seed=123456789;iterations=25000000;threshold=2147483648
#
# packet_classifier — 25M iterations that pick one of two 32-bit LCGs
# from the current state. The branch is data-dependent and about 50/50,
# so no predictor can learn it.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
THRESHOLD = 1 << 31
MASK = 0xFFFFFFFF

state = 123456789
for _ in range(25_000_000):
    if state < THRESHOLD:
        state = (state * 1664525 + 1013904223) & MASK
    else:
        state = (state * 22695477 + 1) & MASK

print(state & 0x7FFFFFFFFFFFFFFF)
