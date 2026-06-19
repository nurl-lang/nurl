// collatz — longest Collatz chain length for starts in [1, 100000).
function steps(n) {
    let c = 0;
    while (n > 1) {
        n = n % 2 === 0 ? n / 2 : 3 * n + 1;
        c += 1;
    }
    return c;
}

let best = 0;
for (let k = 1; k < 100000; k++) {
    const s = steps(k);
    if (s > best) best = s;
}
console.log(best);
