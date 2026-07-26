// benchmark-contract: ring-write;seed=123456789;iterations=20000000;words=64;value=state32x2
//
// ring_write — 20M LCG steps, each storing one 64-bit word into a
// 64-slot ring buffer.
//
// Representation: the stored word is `(state << 32) | state`, i.e. the
// same 32-bit value twice, so the ring is a `Uint32Array` of 2×64
// halves — the standard JS way to hold 64-bit words without paying for
// a BigInt allocation per store. The arithmetic is identical; only the
// final fold needs a real 64-bit XOR, and `xor64` does that on the two
// halves. `Math.imul` keeps the LCG multiply exact: 32-bit wrap-around
// is what it is defined to do, where a plain `*` would overflow the
// 53-bit mantissa.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const ITERATIONS = 20000000;
const buf = new Uint32Array(128); // 64 slots × (low, high)

let state = 123456789;
for (let i = 0; i < ITERATIONS; i++) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    const slot = (i & 63) << 1;
    buf[slot] = state;
    buf[slot + 1] = state;
}

// checksum = ((state << 32) | state) ^ buf[0], in exact 64-bit terms.
const highXor = (state ^ buf[1]) >>> 0;
const lowXor = (state ^ buf[0]) >>> 0;
const result = (BigInt(highXor) << 32n) | BigInt(lowXor);

console.log((result & 0x7fffffffffffffffn).toString());
