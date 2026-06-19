// rot13 — ROT13 every lowercase letter and print the sum of the byte values.
const text = "the quick brown fox jumps over the lazy dog and then the slow purple turtle naps";
let total = 0;
for (let i = 0; i < text.length; i++) {
    let o = text.charCodeAt(i);
    if (o >= 97 && o <= 122) {
        o = 97 + ((o - 97 + 13) % 26);
    }
    total += o;
}
console.log(total);
