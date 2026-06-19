// rot13 — ROT13 every lowercase letter and print the sum of the byte values.
fn main() {
    let text = "the quick brown fox jumps over the lazy dog and then the slow purple turtle naps";
    let mut total: i64 = 0;
    for &b in text.as_bytes() {
        let mut o = b as i64;
        if (97..=122).contains(&o) {
            o = 97 + (o - 97 + 13) % 26;
        }
        total += o;
    }
    println!("{}", total);
}
