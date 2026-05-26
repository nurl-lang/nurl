#!/usr/bin/env python3
# lcg — 100M iterations of the MMIX LCG. Python integers are bignum,
# so we explicitly mask to i64 each step to match the i64-wrap
# semantics every other language gets for free.
x = 1
MASK = (1 << 64) - 1
SIGN = 1 << 63
for _ in range(100_000_000):
    x = (x * 6364136223846793005 + 1442695040888963407) & MASK
# print signed i64 (matches NURL/Rust/Node output)
print(x - (1 << 64) if x & SIGN else x)
