#!/usr/bin/env python3
# benchmark-contract: ring-write-xs13;seed=123456789;iterations=20000000;words=64;value=state32x2;xorshift=13
#
# ring_write — 20M LCG steps, each storing one 64-bit word into a
# 64-slot ring buffer. The list write and the index arithmetic are what
# this row measures on top of the LCG.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
buf = [0] * 64
state = 123456789

for i in range(20_000_000):
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    state ^= state >> 13
    buf[i & 63] = (state << 32) | state

result = ((state << 32) | state) ^ buf[0]
print(result & 0x7FFFFFFFFFFFFFFF)
