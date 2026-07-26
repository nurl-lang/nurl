// benchmark-contract: lcg64-mmix-xs33;seed=1;iterations=20000000;mul=6364136223846793005;add=1442695040888963407;xorshift=33
//
// lcg — 20M iterations of the MMIX LCG with a PCG-style xorshift mix
// each step (see the C peer for why the mix is there). Unsigned
// arithmetic, printed as i64 to match the peers.
fn main() {
    let mut x: u64 = 1;
    for _ in 0..20_000_000u64 {
        x = x
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        x ^= x >> 33;
    }
    println!("{}", x as i64);
}
