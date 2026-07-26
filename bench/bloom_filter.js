// benchmark-contract: bloom-filter;seed=123456789;build=10000;queries=4000000;words=256;lanes=4
//
// bloom_filter — build a 256-word split-block Bloom filter from 10k
// 64-bit hashes, then run 4M membership queries against it.
//
// Representation: BigInt, in a `BigUint64Array` for the filter. Both
// the hash and the filter words are genuinely 64 bits wide here — bit
// indices run to 63 and the hash slices reach bit 36 — so there is no
// Number-based path that computes the same value. This is the exact
// 64-bit tool modern JS offers, and its cost is part of the answer.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const BUILD = 10000;
const QUERIES = 4000000;
const filter = new BigUint64Array(256);

let state = 123456789;
function lcgStep() {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state;
}

for (let i = 0; i < BUILD; i++) {
    const h = (BigInt(lcgStep()) << 32n) | BigInt(lcgStep());
    for (let lane = 0n; lane < 4n; lane++) {
        const word = Number((h >> (lane * 8n)) & 255n);
        const bit = (h >> (lane * 11n + 3n)) & 63n;
        filter[word] |= 1n << bit;
    }
}

let hits = 0;
for (let i = 0; i < QUERIES; i++) {
    const h = (BigInt(lcgStep()) << 32n) | BigInt(lcgStep());
    let hit = 1n;
    for (let lane = 0n; lane < 4n; lane++) {
        const word = Number((h >> (lane * 8n)) & 255n);
        const bit = (h >> (lane * 11n + 3n)) & 63n;
        hit &= (filter[word] >> bit) & 1n;
    }
    hits += Number(hit);
}

console.log(hits);
