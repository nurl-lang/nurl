// benchmark-contract: branch-lcg32;seed=123456789;iterations=25000000;threshold=2147483648
//
// packet_classifier — 25M iterations that pick one of two 32-bit LCGs
// from the current state. The branch is data-dependent and about 50/50.
//
// Representation: Numbers. Everything here stays inside 32 bits, and
// `Math.imul` performs the 32-bit wrapping multiply exactly — a plain
// `state * 22695477` would exceed the 53-bit mantissa and round.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const ITERATIONS = 25000000;
const THRESHOLD = 2147483648;

let state = 123456789;
for (let i = 0; i < ITERATIONS; i++) {
    if (state < THRESHOLD) {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    } else {
        state = (Math.imul(state, 22695477) + 1) >>> 0;
    }
}

console.log(state);
