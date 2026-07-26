// benchmark-contract: binary-search;seed=123456789;queries=5000000;values=even-0..126;algorithm=lower-bound
//
// binary_search — 5M lower-bound searches over a 64-entry sorted table
// of the even numbers 0..126, with LCG-drawn targets in 0..127.
//
// Representation: Numbers. The table and the hit counter are far inside
// 32 bits; only the final XOR needs the `>>> 0` to read back unsigned.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const QUERIES = 5000000;
const values = new Uint32Array(64);
for (let i = 0; i < 64; i++) {
    values[i] = 2 * i;
}

let state = 123456789;
let hits = 0;

for (let q = 0; q < QUERIES; q++) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    const target = state & 127;

    let low = 0;
    let high = 64;
    while (low < high) {
        const middle = low + ((high - low) >> 1);
        if (values[middle] < target) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }

    if (low < 64 && values[low] === target) {
        hits += 1;
    }
}

console.log((state ^ hits) >>> 0);
