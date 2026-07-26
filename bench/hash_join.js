// benchmark-contract: hash-join;seed=123456789;build=160;queries=500000;cap=256;bloom=64;group=16;probe=alternating-built-random
//
// hash_join — build a 256-slot open-addressed hash table (7-bit control
// fingerprints, 16-wide group probing, partitioned into 4 sub-tables)
// from 160 rows, then probe it 500k times behind a 4-lane Bloom
// pre-filter and XOR-fold the matches through a 64-slot compaction
// buffer.
//
// Representation: BigInt. Keys, payloads and the Bloom words are all
// full 64-bit values — the fingerprint is drawn from bit 57, the Bloom
// bit index reaches bit 39, and the payload fold is a 64-bit XOR — so
// nothing here fits in a Number without splitting every value by hand.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const CAP = 256;
const BLOOM_WORDS = 64;
const GROUP = 16n;
const COMPACT_CHUNK = 64;
const BUILD_ROWS = 160;
const TOTAL_QUERIES = 500000;

let state = 123456789;
function lcgStep() {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state;
}

function draw64() {
    const high = BigInt(lcgStep());
    const low = BigInt(lcgStep());
    return (high << 32n) | low;
}

function fp7(key) {
    return ((key >> 57n) & 0x7fn) + 1n;
}

function bloomAdd(bloom, h) {
    for (let lane = 0n; lane < 4n; lane++) {
        const bitIdx = (h >> (lane * 13n)) & 4095n;
        bloom[Number(bitIdx >> 6n)] |= 1n << (bitIdx & 63n);
    }
}

function bloomMaybe(bloom, h) {
    for (let lane = 0n; lane < 4n; lane++) {
        const bitIdx = (h >> (lane * 13n)) & 4095n;
        if (((bloom[Number(bitIdx >> 6n)] >> (bitIdx & 63n)) & 1n) === 0n) {
            return false;
        }
    }
    return true;
}

function groupedInsert(ctrl, keys, vals, key, val, partitioned) {
    const fp = fp7(key);
    const part = (key >> 62n) & 3n;
    let group = partitioned ? (key & 63n) & 48n : (key & 255n) & 240n;
    const rounds = partitioned ? 4n : 16n;

    for (let r = 0n; r < rounds; r++) {
        for (let lane = 0n; lane < GROUP; lane++) {
            const idx = Number(
                partitioned ? (part << 6n) | ((group + lane) & 63n) : (group + lane) & 255n,
            );
            const c = ctrl[idx];
            if (c === 0n) {
                ctrl[idx] = fp;
                keys[idx] = key;
                vals[idx] = val;
                return;
            }
            if (c === fp && keys[idx] === key) {
                vals[idx] = val;
                return;
            }
        }
        group = partitioned ? (group + GROUP) & 63n : (group + GROUP) & 255n;
    }

    let idx = partitioned ? (part << 6n) | (key & 63n) : key & 255n;
    const limit = partitioned ? 64n : 256n;
    for (let i = 0n; i < limit; i++) {
        const slot = Number(idx);
        const c = ctrl[slot];
        if (c === 0n || (c === fp && keys[slot] === key)) {
            ctrl[slot] = fp;
            keys[slot] = key;
            vals[slot] = val;
            return;
        }
        idx = partitioned ? (part << 6n) | ((idx + 1n) & 63n) : (idx + 1n) & 255n;
    }
}

// Returns the payload on a hit, or null on a miss. An empty control slot
// ends the scan — the same early-out the peers use.
function groupedProbe(ctrl, keys, vals, probeKey, partitioned) {
    const fp = fp7(probeKey);
    const part = (probeKey >> 62n) & 3n;
    let group = partitioned ? (probeKey & 63n) & 48n : (probeKey & 255n) & 240n;
    const rounds = partitioned ? 4n : 16n;

    for (let r = 0n; r < rounds; r++) {
        for (let lane = 0n; lane < GROUP; lane++) {
            const idx = Number(
                partitioned ? (part << 6n) | ((group + lane) & 63n) : (group + lane) & 255n,
            );
            const c = ctrl[idx];
            if (c === 0n) {
                return null;
            }
            if (c === fp && keys[idx] === probeKey) {
                return vals[idx];
            }
        }
        group = partitioned ? (group + GROUP) & 63n : (group + GROUP) & 255n;
    }

    return null;
}

const ctrl = new BigUint64Array(CAP);
const keys = new BigUint64Array(CAP);
const vals = new BigUint64Array(CAP);
const reducerBloom = new BigUint64Array(BLOOM_WORDS);
const compact = new BigUint64Array(COMPACT_CHUNK);
const builtKeys = new BigUint64Array(BUILD_ROWS);

const usePartitioned = BUILD_ROWS >= 128 && TOTAL_QUERIES >= 200000;

for (let row = 0; row < BUILD_ROWS; row++) {
    const key = draw64();
    const val = draw64();
    builtKeys[row] = key;
    bloomAdd(reducerBloom, key);
    groupedInsert(ctrl, keys, vals, key, val, usePartitioned);
}

let sum = 0n;
let compactLen = 0;
for (let query = 0; query < TOTAL_QUERIES; query++) {
    // Both words are drawn on every query so the LCG stream advances
    // identically down either side of the branch; every second query then
    // probes a key that was actually built, because a random 64-bit key
    // never matches a 160-row table.
    const drawn = draw64();
    const probeKey = (query & 1) === 0 ? builtKeys[(query >> 1) % BUILD_ROWS] : drawn;

    if (!bloomMaybe(reducerBloom, probeKey)) {
        continue;
    }

    const found = groupedProbe(ctrl, keys, vals, probeKey, usePartitioned);
    if (found === null) {
        continue;
    }

    compact[compactLen] = found;
    compactLen += 1;
    if (compactLen === COMPACT_CHUNK) {
        for (let j = 0; j < COMPACT_CHUNK; j++) {
            sum ^= compact[j];
        }
        compactLen = 0;
    }
}

for (let j = 0; j < compactLen; j++) {
    sum ^= compact[j];
}

console.log((sum & 0x7fffffffffffffffn).toString());
