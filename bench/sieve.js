// sieve — Sieve of Eratosthenes, count primes ≤ 10_000_000.
const N = 10_000_000;
const mark = new Uint8Array(N);
mark[0] = 1;
mark[1] = 1;
let p = 2;
while (p * p < N) {
    if (mark[p] === 0) {
        for (let m = p * p; m < N; m += p) mark[m] = 1;
    }
    p++;
}
let count = 0;
for (let k = 2; k < N; k++) if (mark[k] === 0) count++;
console.log(count);
