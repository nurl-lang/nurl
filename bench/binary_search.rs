// benchmark-contract: binary-search;seed=123456789;queries=5000000;values=even-0..126;algorithm=lower-bound
const ITERATIONS: u64 = 5_000_000;
const SEED: u64 = 123_456_789;

fn finish(value: u64) -> ! {
    // See the C peer: one decimal line, masked to 63 bits.
    println!("{}", value & 0x7fff_ffff_ffff_ffff);
    std::process::exit(0)
}

fn main() {
    let values: [u64; 64] = [
        0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46,
        48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76, 78, 80, 82, 84, 86, 88, 90, 92,
        94, 96, 98, 100, 102, 104, 106, 108, 110, 112, 114, 116, 118, 120, 122, 124, 126,
    ];
    let mut state = SEED;
    let mut hits = 0u64;
    let mut i = 0u64;

    while i < ITERATIONS {
        state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223) & 0xffff_ffff;
        let target = state & 127;
        let mut low = 0usize;
        let mut high = 64usize;
        while low < high {
            let middle = low + ((high - low) >> 1);
            if values[middle] < target {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        if low < 64 && values[low] == target {
            hits = hits.wrapping_add(1);
        }
        i += 1;
    }

    finish(state ^ hits);
}
