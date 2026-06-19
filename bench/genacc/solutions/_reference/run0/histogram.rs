// histogram — highest single-digit count in an embedded string.
fn main() {
    let text = "314159265358979";
    let mut hist = [0i64; 10];
    for &c in text.as_bytes() {
        if (48..=57).contains(&c) {
            hist[(c - 48) as usize] += 1;
        }
    }
    let maxc = *hist.iter().max().unwrap();
    println!("{}", maxc);
}
