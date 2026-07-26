// benchmark-contract: ring-write-xs13;seed=123456789;iterations=20000000;words=64;value=state32x2;xorshift=13
const ITERATIONS: u64 = 20_000_000;
const WORDS: usize = 64;
const SEED: u64 = 123_456_789;
const MASK: u64 = 0xffff_ffff;

fn finish(value: u64) -> ! {
    // See the C peer: one decimal line, masked to 63 bits.
    println!("{}", value & 0x7fff_ffff_ffff_ffff);
    std::process::exit(0)
}

fn main() {
    let mut state = SEED;
    let mut buf = [0u64; WORDS];
    let mask = (WORDS as u64) - 1;
    let mut i = 0u64;

    while i < ITERATIONS {
        state = state
            .wrapping_mul(1_664_525)
            .wrapping_add(1_013_904_223)
            & MASK;
        state ^= state >> 13;
        buf[(i & mask) as usize] = (state << 32) | state;
        i += 1;
    }

    finish(((state << 32) | state) ^ buf[0]);
}
