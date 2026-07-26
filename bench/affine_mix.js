// benchmark-contract: affine-mix;seed=123456789;iterations=20000000;mask=0x03ffffffffffffff
//
// affine_mix — 20M rounds of two chained affine steps over a 58-bit
// state.
//
// Representation: BigInt. `state << 3` needs 61 bits and a JS Number is
// only exact to 53, so unlike the other 32-bit kernels in this set
// there is no Number-based path that computes the same value. BigInt is
// what modern JS offers for exact 64-bit-class integers, and that cost
// is part of the answer this row reports.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const MASK = 0x03ffffffffffffffn;
const ITERATIONS = 20000000n;

let state = 123456789n;
for (let i = 0n; i < ITERATIONS; i++) {
    state = ((state << 3n) + i) & MASK;
    state = ((state << 2n) - 3n) & MASK;
}

console.log((state & 0x7fffffffffffffffn).toString());
