// lcg — 100M iterations of the MMIX LCG, i64 wrap-around semantics.
fn main() {
    let mut x: i64 = 1;
    for _ in 0..100_000_000 {
        x = x.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
    }
    println!("{}", x);
}
