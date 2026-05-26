// lcg — 100M iterations of the MMIX LCG via BigInt (Number's 53-bit
// mantissa cannot hold the i64 intermediate without precision loss).
let x = 1n;
const A = 6364136223846793005n;
const C = 1442695040888963407n;
const MASK = (1n << 64n) - 1n;
const SIGN = 1n << 63n;
for (let i = 0; i < 100_000_000; i++) {
    x = (x * A + C) & MASK;
}
console.log((x & SIGN) ? (x - (1n << 64n)).toString() : x.toString());
