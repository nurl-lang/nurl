#!/usr/bin/env python3
# benchmark-contract: affine-mix-xs9;seed=123456789;iterations=20000000;mask=0x03ffffffffffffff;xorshift=9
#
# affine_mix — 20M rounds of two chained affine steps over a 58-bit
# state. Python integers are arbitrary precision, so every step masks
# back to 58 bits explicitly to get the fixed-width semantics the other
# four languages have built in.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
MASK = 0x03FFFFFFFFFFFFFF

state = 123456789
for i in range(20_000_000):
    state = ((state << 3) + i) & MASK
    state ^= state >> 9
    state = ((state << 2) - 3) & MASK

print(state & 0x7FFFFFFFFFFFFFFF)
