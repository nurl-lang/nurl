// histogram — highest single-digit count in an embedded string.
const text = "314159265358979";
const hist = new Array(10).fill(0);
for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c >= 48 && c <= 57) hist[c - 48] += 1;
}
console.log(Math.max(...hist));
