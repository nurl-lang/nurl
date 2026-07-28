#!/usr/bin/env python3
# benchmark-contract: hash-join;seed=123456789;build=160;queries=5000000;cap=256;bloom=64;group=16;probe=alternating-built-random
#
# hash_join — build a 256-slot open-addressed hash table (7-bit control
# fingerprints, 16-wide group probing, partitioned into 4 sub-tables)
# from 160 rows, then probe it 500k times behind a 4-lane Bloom
# pre-filter and XOR-fold the matches through a 64-slot compaction
# buffer. The heaviest shape in the set: a cheap early-out plus a rare,
# branchy slow path.
#
# Contract: print exactly one line — the checksum, masked to 63 bits.
CAP = 256
BLOOM_WORDS = 64
GROUP = 16
COMPACT_CHUNK = 64
BUILD_ROWS = 160
TOTAL_QUERIES = 5_000_000

state = 123456789


def lcg_step():
    global state
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    return state


def draw64():
    high = lcg_step()
    low = lcg_step()
    return (high << 32) | low


def fp7(key):
    return ((key >> 57) & 0x7F) + 1


def bloom_add(bloom, h):
    for lane in range(4):
        bit_idx = (h >> (lane * 13)) & 4095
        bloom[bit_idx >> 6] |= 1 << (bit_idx & 63)


def bloom_maybe(bloom, h):
    for lane in range(4):
        bit_idx = (h >> (lane * 13)) & 4095
        if ((bloom[bit_idx >> 6] >> (bit_idx & 63)) & 1) == 0:
            return False
    return True


def grouped_insert(ctrl, keys, vals, key, val, partitioned):
    fp = fp7(key)
    part = (key >> 62) & 3
    group = ((key & 63) & 48) if partitioned else ((key & 255) & 240)
    rounds = 4 if partitioned else 16

    for _ in range(rounds):
        for lane in range(GROUP):
            idx = ((part << 6) | ((group + lane) & 63)) if partitioned else ((group + lane) & 255)
            c = ctrl[idx]
            if c == 0:
                ctrl[idx] = fp
                keys[idx] = key
                vals[idx] = val
                return
            if c == fp and keys[idx] == key:
                vals[idx] = val
                return
        group = ((group + GROUP) & 63) if partitioned else ((group + GROUP) & 255)

    idx = ((part << 6) | (key & 63)) if partitioned else (key & 255)
    limit = 64 if partitioned else 256
    for _ in range(limit):
        c = ctrl[idx]
        if c == 0 or (c == fp and keys[idx] == key):
            ctrl[idx] = fp
            keys[idx] = key
            vals[idx] = val
            return
        idx = ((part << 6) | ((idx + 1) & 63)) if partitioned else ((idx + 1) & 255)


# Returns the payload on a hit, or None on a miss. An empty control slot
# ends the scan — the same early-out the peers use.
def grouped_probe(ctrl, keys, vals, probe_key, partitioned):
    fp = fp7(probe_key)
    part = (probe_key >> 62) & 3
    group = ((probe_key & 63) & 48) if partitioned else ((probe_key & 255) & 240)
    rounds = 4 if partitioned else 16

    for _ in range(rounds):
        for lane in range(GROUP):
            idx = ((part << 6) | ((group + lane) & 63)) if partitioned else ((group + lane) & 255)
            c = ctrl[idx]
            if c == 0:
                return None
            if c == fp and keys[idx] == probe_key:
                return vals[idx]
        group = ((group + GROUP) & 63) if partitioned else ((group + GROUP) & 255)

    return None


ctrl = [0] * CAP
keys = [0] * CAP
vals = [0] * CAP
reducer_bloom = [0] * BLOOM_WORDS
compact = [0] * COMPACT_CHUNK
built_keys = [0] * BUILD_ROWS

use_partitioned = BUILD_ROWS >= 128 and TOTAL_QUERIES >= 200_000

for row in range(BUILD_ROWS):
    key = draw64()
    val = draw64()
    built_keys[row] = key
    bloom_add(reducer_bloom, key)
    grouped_insert(ctrl, keys, vals, key, val, use_partitioned)

total = 0
compact_len = 0
for query in range(TOTAL_QUERIES):
    # Both words are drawn on every query so the LCG stream advances
    # identically down either side of the branch; every second query then
    # probes a key that was actually built, because a random 64-bit key
    # never matches a 160-row table.
    drawn = draw64()
    probe_key = built_keys[(query >> 1) % BUILD_ROWS] if (query & 1) == 0 else drawn

    if not bloom_maybe(reducer_bloom, probe_key):
        continue

    found = grouped_probe(ctrl, keys, vals, probe_key, use_partitioned)
    if found is None:
        continue

    compact[compact_len] = found
    compact_len += 1
    if compact_len == COMPACT_CHUNK:
        for j in range(COMPACT_CHUNK):
            total ^= compact[j]
        compact_len = 0

for j in range(compact_len):
    total ^= compact[j]

print(total & 0x7FFFFFFFFFFFFFFF)
