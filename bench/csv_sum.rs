// csv_sum — sum every integer in an embedded ','/';'-separated grid.
fn main() {
    let text = "12,3,45;6,78,9;100,2,33";
    let mut total = 0i64;
    let mut cur = 0i64;
    for &c in text.as_bytes() {
        if (48..=57).contains(&c) {
            cur = cur * 10 + (c as i64 - 48);
        } else {
            total += cur;
            cur = 0;
        }
    }
    total += cur;
    println!("{}", total);
}
