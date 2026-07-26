// benchmark-contract: branch-lcg32;seed=123456789;iterations=25000000;threshold=2147483648
const ITERATIONS: u64 = 25_000_000;
const THRESHOLD: u64 = 1u64 << 31;
const SEED: u64 = 123_456_789;
const MASK: u64 = 0xffff_ffff;

fn finish(value: u64) -> ! {
    // See the C peer: one decimal line, masked to 63 bits.
    println!("{}", value & 0x7fff_ffff_ffff_ffff);
    std::process::exit(0)
}

fn main() {
    let mut state = SEED;
    let mut i = 0u64;
    while i < ITERATIONS {
        if state < THRESHOLD {
            state = state
                .wrapping_mul(1_664_525)
                .wrapping_add(1_013_904_223)
                & MASK;
        } else {
            state = state.wrapping_mul(22_695_477).wrapping_add(1) & MASK;
        }
        i += 1;
    }
    finish(state);
}
