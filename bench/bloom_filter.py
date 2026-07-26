#!/usr/bin/env python3
# benchmark-contract: bloom-filter;seed=123456789;build=10000;queries=4000000;words=256;lanes=4
#
# bloom_filter — build a 256-word split-block Bloom filter from 10k
# 64-bit hashes, then run 4M membership queries against it. Each
# operation touches 4 lanes whose word index and bit index come from
# different slices of the hash: 4 unpredictable loads per query over a
# 2 KB working set.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
state = 123456789
filter_words = [0] * 256


def lcg_step():
    global state
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    return state


for _ in range(10_000):
    h = (lcg_step() << 32) | lcg_step()
    for lane in range(4):
        word = (h >> (lane * 8)) & 255
        bit = (h >> (lane * 11 + 3)) & 63
        filter_words[word] |= 1 << bit

hits = 0
for _ in range(4_000_000):
    h = (lcg_step() << 32) | lcg_step()
    hit = 1
    for lane in range(4):
        word = (h >> (lane * 8)) & 255
        bit = (h >> (lane * 11 + 3)) & 63
        hit &= (filter_words[word] >> bit) & 1
    hits += hit

print(hits & 0x7FFFFFFFFFFFFFFF)
