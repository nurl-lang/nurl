// benchmark-contract: histogram;seed=123456789;iterations=20000000;bins=64;index=state&63
const ITERATIONS: u64 = 20_000_000;
const BINS: usize = 64;
const SEED: u64 = 123_456_789;
const MASK: u64 = 0xffff_ffff;

fn finish(value: u64) -> ! {
    // See the C peer: one decimal line, masked to 63 bits.
    println!("{}", value & 0x7fff_ffff_ffff_ffff);
    std::process::exit(0)
}

fn main() {
    let mut state = SEED;
    let mut bins = [0u64; BINS];

    let mut i = 0u64;
    while i < ITERATIONS {
        state = state
            .wrapping_mul(1_664_525)
            .wrapping_add(1_013_904_223)
            & MASK;
        let index = (state & 63) as usize;
        bins[index] = bins[index].wrapping_add(1);
        i += 1;
    }

    let mut checksum = state;
    let mut index = 0usize;
    while index < BINS {
        checksum ^= bins[index].wrapping_mul(index as u64 + 1);
        index += 1;
    }

    finish(checksum);
}
