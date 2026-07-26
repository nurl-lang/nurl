// benchmark-contract: ring-write;seed=123456789;iterations=50000000;words=64;value=state32x2
const ITERATIONS: u64 = 50_000_000;
const WORDS: usize = 64;
const SEED: u64 = 123_456_789;
const MASK: u64 = 0xffff_ffff;

fn finish(value: u64) -> ! {
    #[cfg(bench_verify)]
    std::io::Write::write_all(&mut std::io::stdout(), &value.to_le_bytes()).unwrap();
    std::process::exit((value & 0x7f) as i32)
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
        buf[(i & mask) as usize] = (state << 32) | state;
        i += 1;
    }

    finish(((state << 32) | state) ^ buf[0]);
}
