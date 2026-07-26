// benchmark-contract: affine-mix;seed=123456789;iterations=50000000;mask=0x03ffffffffffffff
const ITERATIONS: u64 = 50_000_000;
const SEED: u64 = 123_456_789;
const MASK: u64 = 0x03ff_ffff_ffff_ffff;

fn finish(value: u64) -> ! {
    #[cfg(bench_verify)]
    std::io::Write::write_all(&mut std::io::stdout(), &value.to_le_bytes()).unwrap();
    std::process::exit((value & 0x7f) as i32)
}

fn main() {
    let mut state = SEED;
    let mut i = 0u64;
    while i < ITERATIONS {
        state = (state << 3).wrapping_add(i) & MASK;
        state = (state << 2).wrapping_sub(3) & MASK;
        i += 1;
    }
    finish(state);
}
