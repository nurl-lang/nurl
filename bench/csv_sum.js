// csv_sum — sum every integer in an embedded ','/';'-separated grid.
const text = "12,3,45;6,78,9;100,2,33";
let total = 0;
let cur = 0;
for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c >= 48 && c <= 57) {
        cur = cur * 10 + (c - 48);
    } else {
        total += cur;
        cur = 0;
    }
}
total += cur;
console.log(total);
