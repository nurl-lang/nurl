// quicksort — sort 5000 LCG ints in place, print a position-weighted checksum.
function qsort(a, lo, hi) {
    if (lo >= hi) return;
    const pivot = a[hi];
    let st = lo;
    for (let j = lo; j < hi; j++) {
        if (a[j] < pivot) {
            [a[st], a[j]] = [a[j], a[st]];
            st += 1;
        }
    }
    [a[st], a[hi]] = [a[hi], a[st]];
    qsort(a, lo, st - 1);
    qsort(a, st + 1, hi);
}

const N = 5000;
const a = new Array(N).fill(0);
let x = 1;
for (let i = 0; i < N; i++) {
    x = (x * 1103515245 + 12345) % 1048576;
    a[i] = x;
}
qsort(a, 0, N - 1);
let total = 0;
for (let k = 0; k < N; k++) {
    total += (k + 1) * a[k];
}
console.log(total);
