// benchmark-contract: affine-mix-xs9;seed=123456789;iterations=20000000;mask=0x03ffffffffffffff;xorshift=9
const ITERATIONS: u64 = 20_000_000;
const SEED: u64 = 123_456_789;
const MASK: u64 = 0x03ff_ffff_ffff_ffff;

fn finish(value: u64) -> ! {
    // See the C peer: one decimal line, masked to 63 bits.
    println!("{}", value & 0x7fff_ffff_ffff_ffff);
    std::process::exit(0)
}

fn main() {
    let mut state = SEED;
    let mut i = 0u64;
    while i < ITERATIONS {
        state = (state << 3).wrapping_add(i) & MASK;
        state ^= state >> 9;
        state = (state << 2).wrapping_sub(3) & MASK;
        i += 1;
    }
    finish(state);
}
