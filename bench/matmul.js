// matmul — multiply two 128x128 integer matrices, print the trace.
const N = 128;
const a = new Array(N * N).fill(0);
const b = new Array(N * N).fill(0);
const c = new Array(N * N).fill(0);

for (let i = 0; i < N; i++) {
    for (let j = 0; j < N; j++) {
        const idx = i * N + j;
        a[idx] = idx % 7;
        b[idx] = (i + j) % 5;
    }
}

for (let ri = 0; ri < N; ri++) {
    for (let cj = 0; cj < N; cj++) {
        let s = 0;
        for (let k = 0; k < N; k++) {
            s += a[ri * N + k] * b[k * N + cj];
        }
        c[ri * N + cj] = s;
    }
}

let tr = 0;
for (let d = 0; d < N; d++) {
    tr += c[d * N + d];
}
console.log(tr);
