// benchmark-contract: prefix-scan;seed=123456789;batches=1000000;width=16;value-mask=65535
//
// prefix_scan — 1M batches of "fill 16 slots from the LCG, then run an
// in-place running sum over them".
//
// Representation: Numbers. The slot values are masked to 16 bits and
// the running sum of 16 of them stays under 2^20, so a `Uint32Array`
// holds them exactly.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const BATCHES = 1000000;
const values = new Uint32Array(16);

let state = 123456789;
let checksum = 0;

for (let batch = 0; batch < BATCHES; batch++) {
    for (let index = 0; index < 16; index++) {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
        values[index] = state & 0xffff;
    }
    for (let index = 1; index < 16; index++) {
        values[index] += values[index - 1];
    }
    checksum = (checksum ^ values[15]) >>> 0;
}

console.log((state ^ checksum) >>> 0);
