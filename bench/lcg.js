// benchmark-contract: lcg64-mmix-xs33;seed=1;iterations=20000000;mul=6364136223846793005;add=1442695040888963407;xorshift=33
//
// lcg — 20M iterations of the MMIX LCG with a PCG-style xorshift mix
// each step (see the C peer for why the mix is there), via BigInt
// (Number's 53-bit mantissa cannot hold the i64 intermediate without
// precision loss).
let x = 1n;
const A = 6364136223846793005n;
const C = 1442695040888963407n;
const MASK = (1n << 64n) - 1n;
const SIGN = 1n << 63n;
for (let i = 0; i < 20_000_000; i++) {
    x = (x * A + C) & MASK;
    x ^= x >> 33n;
}
console.log((x & SIGN) ? (x - (1n << 64n)).toString() : x.toString());
