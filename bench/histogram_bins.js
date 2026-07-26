// benchmark-contract: histogram;seed=123456789;iterations=20000000;bins=64;index=state&63
//
// histogram_bins — 20M LCG steps, each incrementing one of 64 bins at a
// data-dependent index, then a weighted XOR fold over the bins.
//
// Representation: Numbers, with the bins in a `Uint32Array` (each bin
// tops out near 20M/64 counts, and the weighted products stay under
// 2^31, so the 32-bit XOR is exact). `>>> 0` after each XOR restores
// the unsigned reading of the int32 result.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const ITERATIONS = 20000000;
const bins = new Uint32Array(64);

let state = 123456789;
for (let i = 0; i < ITERATIONS; i++) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    bins[state & 63] += 1;
}

let checksum = state;
for (let index = 0; index < 64; index++) {
    checksum = (checksum ^ (bins[index] * (index + 1))) >>> 0;
}

console.log(checksum);
