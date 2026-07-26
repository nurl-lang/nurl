#!/usr/bin/env python3
# benchmark-contract: lcg64-mmix-xs33;seed=1;iterations=20000000;mul=6364136223846793005;add=1442695040888963407;xorshift=33
#
# lcg — 20M iterations of the MMIX LCG with a PCG-style xorshift mix
# each step (see the C peer for why the mix is there). Python integers
# are bignum, so we explicitly mask to 64 bits each step to match the
# wrap semantics every other language gets for free.
x = 1
MASK = (1 << 64) - 1
SIGN = 1 << 63
for _ in range(20_000_000):
    x = (x * 6364136223846793005 + 1442695040888963407) & MASK
    x ^= x >> 33
# print signed i64 (matches NURL/Rust/Node output)
print(x - (1 << 64) if x & SIGN else x)
