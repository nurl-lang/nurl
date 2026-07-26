#!/usr/bin/env python3
# benchmark-contract: histogram-xs13;seed=123456789;iterations=20000000;bins=64;index=state&63;xorshift=13
#
# histogram_bins — 20M LCG steps, each incrementing one of 64 bins at a
# data-dependent index, then a weighted XOR fold over the bins.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
bins = [0] * 64
state = 123456789

for _ in range(20_000_000):
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    state ^= state >> 13
    index = state & 63
    bins[index] += 1

checksum = state
for index in range(64):
    checksum ^= bins[index] * (index + 1)

print(checksum & 0x7FFFFFFFFFFFFFFF)
