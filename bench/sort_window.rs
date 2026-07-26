// benchmark-contract: sort-window;seed=123456789;iterations=5000000;width=8;algorithm=bubble
const ITERATIONS: u64 = 5_000_000;
const SEED: u64 = 123_456_789;
const MASK: u64 = 0xffff_ffff;

fn finish(value: u64) -> ! {
    #[cfg(bench_verify)]
    std::io::Write::write_all(&mut std::io::stdout(), &value.to_le_bytes()).unwrap();
    std::process::exit((value & 0x7f) as i32)
}

fn bubble_sort8(arr: &mut [u64; 8]) {
    let mut pass = 0usize;
    while pass < 8 {
        let mut j = 0usize;
        while j + 1 < 8 - pass {
            if arr[j] > arr[j + 1] {
                arr.swap(j, j + 1);
            }
            j += 1;
        }
        pass += 1;
    }
}

fn main() {
    let mut state = SEED;
    let mut i = 0u64;
    let mut window = [0u64, 1, 2, 3, 4, 5, 6, 7];

    while i < ITERATIONS {
        state = state
            .wrapping_mul(1_664_525)
            .wrapping_add(1_013_904_223)
            & MASK;

        window[0] = state;
        window[1] = state ^ 0xa5a5_a5a5;
        window[2] = state.wrapping_add(i) & MASK;
        window[3] = state.wrapping_mul(3);
        window[4] = state.wrapping_sub(i) & MASK;
        window[5] = state >> 3;
        window[6] = state << 1;
        window[7] = state.wrapping_add(7) & MASK;

        bubble_sort8(&mut window);
        state = state ^ window[0] ^ window[7];
        i += 1;
    }

    finish(state);
}
