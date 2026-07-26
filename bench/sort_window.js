// benchmark-contract: sort-window;seed=123456789;iterations=2000000;width=8;algorithm=bubble
//
// sort_window — 2M iterations of "derive 8 values from the LCG state,
// bubble-sort them, fold the extremes back into the state".
//
// Representation: Numbers. Two of the derived slots (`state * 3` and
// `state << 1`) are 64-bit values in the peers, but they stay under
// 2^36 here, which a double holds exactly — so only the XORs need help,
// since JS's `^` is defined on int32. `xor64` does the XOR on the two
// 32-bit halves and reassembles, which is exact for anything under 2^53.
// `state >> 3` and `state << 1` likewise become divide/multiply so they
// do not truncate to 32 bits the way JS's shift operators would.
//
// Contract: print exactly one line — the checksum, masked to 63 bits.
const ITERATIONS = 2000000;
const TWO32 = 4294967296;

function xor64(a, b) {
    const high = (Math.floor(a / TWO32) ^ Math.floor(b / TWO32)) >>> 0;
    const low = ((a >>> 0) ^ (b >>> 0)) >>> 0;
    return high * TWO32 + low;
}

const window8 = [0, 1, 2, 3, 4, 5, 6, 7];
let state = 123456789;

for (let i = 0; i < ITERATIONS; i++) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;

    window8[0] = state;
    window8[1] = xor64(state, 0xa5a5a5a5);
    window8[2] = (state + i) >>> 0;
    window8[3] = state * 3;
    window8[4] = (state - i) >>> 0;
    window8[5] = Math.floor(state / 8);
    window8[6] = state * 2;
    window8[7] = (state + 7) >>> 0;

    for (let pass = 0; pass < 8; pass++) {
        for (let j = 0; j + 1 < 8 - pass; j++) {
            if (window8[j] > window8[j + 1]) {
                const tmp = window8[j];
                window8[j] = window8[j + 1];
                window8[j + 1] = tmp;
            }
        }
    }

    state = xor64(xor64(state, window8[0]), window8[7]);
}

console.log(state.toString());
