// benchmark-contract: hash-join;seed=123456789;build=160;queries=500000;cap=256;bloom=64;group=16
const CAP: usize = 256;
const GROUP: u64 = 16;
const BLOOM_WORDS: usize = 64;
const COMPACT_CHUNK: usize = 64;
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

fn fp7(key: u64) -> u64 {
    ((key >> 57) & 0x7f) + 1
}

fn bloom_add(filter: &mut [u64; BLOOM_WORDS], hash: u64) {
    let mut lane = 0u64;
    while lane < 4 {
        let bit_idx = (hash >> (lane * 13)) & 4095;
        let word = (bit_idx >> 6) as usize;
        let bit = bit_idx & 63;
        filter[word] |= 1u64 << bit;
        lane += 1;
    }
}

fn bloom_maybe(filter: &[u64; BLOOM_WORDS], hash: u64) -> bool {
    let mut lane = 0u64;
    while lane < 4 {
        let bit_idx = (hash >> (lane * 13)) & 4095;
        let word = (bit_idx >> 6) as usize;
        let bit = bit_idx & 63;
        if ((filter[word] >> bit) & 1) == 0 {
            return false;
        }
        lane += 1;
    }
    true
}

fn grouped_insert(
    ctrl: &mut [u64; CAP],
    keys: &mut [u64; CAP],
    vals: &mut [u64; CAP],
    key: u64,
    val: u64,
    partitioned: bool,
) {
    let fp = fp7(key);
    let part = (key >> 62) & 3;
    let mut group = if partitioned {
        (key & 63) & 48
    } else {
        (key & 255) & 240
    };
    let rounds = if partitioned { 4 } else { 16 };

    let mut r = 0u64;
    while r < rounds {
        let mut lane = 0u64;
        while lane < GROUP {
            let idx = if partitioned {
                ((part << 6) | ((group + lane) & 63)) as usize
            } else {
                ((group + lane) & 255) as usize
            };
            let c = ctrl[idx];
            if c == 0 {
                ctrl[idx] = fp;
                keys[idx] = key;
                vals[idx] = val;
                return;
            }
            if c == fp && keys[idx] == key {
                vals[idx] = val;
                return;
            }
            lane += 1;
        }
        group = if partitioned {
            (group + GROUP) & 63
        } else {
            (group + GROUP) & 255
        };
        r += 1;
    }

    let mut idx = if partitioned {
        ((part << 6) | (key & 63)) as usize
    } else {
        (key & 255) as usize
    };
    let limit = if partitioned { 64 } else { 256 };
    let mut i = 0u64;
    while i < limit {
        let c = ctrl[idx];
        if c == 0 || (c == fp && keys[idx] == key) {
            ctrl[idx] = fp;
            keys[idx] = key;
            vals[idx] = val;
            return;
        }
        idx = if partitioned {
            ((part << 6) | ((idx as u64 + 1) & 63)) as usize
        } else {
            (idx + 1) & 255
        };
        i += 1;
    }
}

fn grouped_probe(
    ctrl: &[u64; CAP],
    keys: &[u64; CAP],
    vals: &[u64; CAP],
    probe_key: u64,
    partitioned: bool,
) -> Option<u64> {
    let fp = fp7(probe_key);
    let part = (probe_key >> 62) & 3;
    let mut group = if partitioned {
        (probe_key & 63) & 48
    } else {
        (probe_key & 255) & 240
    };
    let rounds = if partitioned { 4 } else { 16 };

    let mut r = 0u64;
    while r < rounds {
        let mut lane = 0u64;
        while lane < GROUP {
            let idx = if partitioned {
                ((part << 6) | ((group + lane) & 63)) as usize
            } else {
                ((group + lane) & 255) as usize
            };
            let c = ctrl[idx];
            if c == 0 {
                return None;
            }
            if c == fp && keys[idx] == probe_key {
                return Some(vals[idx]);
            }
            lane += 1;
        }
        group = if partitioned {
            (group + GROUP) & 63
        } else {
            (group + GROUP) & 255
        };
        r += 1;
    }

    None
}

fn main() {
    let mut state = SEED;
    let mut ctrl = [0u64; CAP];
    let mut table_keys = [0u64; CAP];
    let mut table_vals = [0u64; CAP];
    let mut reducer_bloom = [0u64; BLOOM_WORDS];
    let mut compact = [0u64; COMPACT_CHUNK];

    let build_rows = 160u64;
    let total_queries = 500_000u64;
    let use_partitioned = build_rows >= 128 && total_queries >= 200_000;

    let mut i = 0u64;
    while i < build_rows {
        let key = (lcg_step(&mut state) << 32) | lcg_step(&mut state);
        let val = (lcg_step(&mut state) << 32) | lcg_step(&mut state);
        bloom_add(&mut reducer_bloom, key);
        grouped_insert(
            &mut ctrl,
            &mut table_keys,
            &mut table_vals,
            key,
            val,
            use_partitioned,
        );
        i += 1;
    }

    let mut sum = 0u64;
    let mut compact_len = 0usize;
    i = 0;
    while i < total_queries {
        let probe_key = (lcg_step(&mut state) << 32) | lcg_step(&mut state);
        if bloom_maybe(&reducer_bloom, probe_key) {
            if let Some(v) =
                grouped_probe(&ctrl, &table_keys, &table_vals, probe_key, use_partitioned)
            {
                compact[compact_len] = v;
                compact_len += 1;
                if compact_len == COMPACT_CHUNK {
                    let mut j = 0usize;
                    while j < COMPACT_CHUNK {
                        sum ^= compact[j];
                        j += 1;
                    }
                    compact_len = 0;
                }
            }
        }
        i += 1;
    }

    let mut j = 0usize;
    while j < compact_len {
        sum ^= compact[j];
        j += 1;
    }

    finish(sum);
}
