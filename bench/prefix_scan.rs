// benchmark-contract: prefix-scan;seed=123456789;batches=1000000;width=16;value-mask=65535
const BATCHES: u64 = 1_000_000;
const SEED: u64 = 123_456_789;

fn finish(value: u64) -> ! {
    // See the C peer: one decimal line, masked to 63 bits.
    println!("{}", value & 0x7fff_ffff_ffff_ffff);
    std::process::exit(0)
}

fn main() {
    let mut values = [0u64; 16];
    let mut state = SEED;
    let mut checksum = 0u64;
    let mut batch = 0u64;

    while batch < BATCHES {
        let mut index = 0usize;
        while index < 16 {
            state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223) & 0xffff_ffff;
            values[index] = state & 0xffff;
            index += 1;
        }

        index = 1;
        while index < 16 {
            values[index] = values[index].wrapping_add(values[index - 1]);
            index += 1;
        }
        checksum ^= values[15];
        batch += 1;
    }

    finish(state ^ checksum);
}
