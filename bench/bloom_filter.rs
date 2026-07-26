// benchmark-contract: bloom-filter;seed=123456789;build=10000;queries=1000000;words=256;lanes=4
const SEED: u64 = 123_456_789;

fn finish(value: u64) -> ! {
    #[cfg(bench_verify)]
    std::io::Write::write_all(&mut std::io::stdout(), &value.to_le_bytes()).unwrap();
    std::process::exit((value & 0x7f) as i32)
}

fn lcg_step(state: &mut u64) -> u64 {
    *state = state
        .wrapping_mul(1_664_525)
        .wrapping_add(1_013_904_223)
        & 0xffff_ffff;
    *state
}

fn split_block_insert(filter: &mut [u64; 256], hash: u64) {
    let mut lane = 0u64;
    while lane < 4 {
        let word = ((hash >> (lane * 8)) & 255) as usize;
        let bit = (hash >> (lane * 11 + 3)) & 63;
        filter[word] |= 1u64 << bit;
        lane += 1;
    }
}

fn split_block_maybe_contains(filter: &[u64; 256], hash: u64) -> u64 {
    let mut hit = 1u64;
    let mut lane = 0u64;
    while lane < 4 {
        let word = ((hash >> (lane * 8)) & 255) as usize;
        let bit = (hash >> (lane * 11 + 3)) & 63;
        hit &= (filter[word] >> bit) & 1;
        lane += 1;
    }
    hit
}

fn main() {
    let mut state = SEED;
    let mut filter = [0u64; 256];

    let mut i = 0u64;
    while i < 10_000 {
        let h = (lcg_step(&mut state) << 32) | lcg_step(&mut state);
        split_block_insert(&mut filter, h);
        i += 1;
    }

    let mut hits = 0u64;
    i = 0;
    while i < 1_000_000 {
        let h = (lcg_step(&mut state) << 32) | lcg_step(&mut state);
        hits = hits.wrapping_add(split_block_maybe_contains(&filter, h));
        i += 1;
    }

    finish(hits);
}
