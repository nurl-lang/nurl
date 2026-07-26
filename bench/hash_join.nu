// benchmark-contract: hash-join;seed=123456789;build=160;queries=500000;cap=256;bloom=64;group=16
//
// hash_join — build a 256-slot open-addressed hash table (7-bit control
// fingerprints, 16-wide group probing, partitioned into 4 sub-tables) from
// 160 rows, then probe it 500k times behind a 4-lane Bloom pre-filter and
// XOR-fold the matches through a 64-slot compaction buffer. The heaviest
// benchmark in the set: it mixes a cheap early-out (almost every probe is
// rejected by the Bloom filter) with a rare, branchy slow path.
//
// NURL has no fixed-size stack array, so ctrl / keys / vals / bloom /
// compact and the LCG state live in `malloc`ed `*u64` blocks. The peers'
// `grouped_probe` returns `int` + out-param (C) / `Option<u64>` (Rust);
// this file follows the C shape — `→ i` plus a one-slot `*u64` out.
//
// Peer protocol (matches hash_join.c / hash_join.rs): the process
// normally prints nothing and reports the checksum through its exit
// status (`checksum & 0x7f`). Passing `--verify` writes the 8
// little-endian checksum bytes to stdout — the C peer spells that
// `-DBENCH_VERIFY`, the Rust peer `--cfg bench_verify`.
& `c` @ putchar i c → i

@ emit_checksum u64 value → v {
    : ~ u64 x value
    : ~ i k 0
    ~ < k 8 {
        ( putchar # i & x 255 )
        = x >> x 8
        = k + k 1
    }
}

@ verify_requested → b {
    : i argc ( nurl_argc )
    : ~ i k 1
    ~ < k argc {
        ? == ( strcmp ( nurl_argv k ) `--verify` ) 0 { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ finish u64 value → i {
    ? ( verify_requested ) { ( emit_checksum value ) } {}
    ^ # i & value 0x7f
}

@ lcg_step * u64 st → u64 {
    : ~ u64 s . st 0
    = s & + * s 1664525 1013904223 0xffffffff
    = . st 0 s
    ^ s
}

// 7-bit control fingerprint, biased by one so 0 stays the "empty slot"
// sentinel.
@ fp7 u64 key → u64 {
    ^ + & >> key 57 0x7f 1
}

@ bloom_add * u64 bloom u64 h → v {
    : ~ i lane 0
    ~ < lane 4 {
        : u64 bit_idx & >> h * lane 13 4095
        : u64 word >> bit_idx 6
        : u64 bit & bit_idx 63
        = . bloom word | . bloom word << # u64 1 bit
        = lane + lane 1
    }
}

@ bloom_maybe * u64 bloom u64 h → b {
    : ~ i lane 0
    ~ < lane 4 {
        : u64 bit_idx & >> h * lane 13 4095
        : u64 word >> bit_idx 6
        : u64 bit & bit_idx 63
        ? == & >> . bloom word bit 1 0 { ^ F } {}
        = lane + lane 1
    }
    ^ T
}

// Group-probing insert: scan 16 consecutive slots at a time for an empty
// slot or a fingerprint+key match, advancing group by group. If the
// grouped scan runs out of rounds, fall back to plain linear probing.
@ grouped_insert * u64 ctrl * u64 keys * u64 vals u64 key u64 val b partitioned → v {
    : u64 fp ( fp7 key )
    : u64 part & >> key 62 3
    : ~ u64 group ? partitioned & & key 63 48 & & key 255 240
    : i rounds ? partitioned 4 16

    : ~ i round 0
    ~ < round rounds {
        : ~ u64 lane 0
        ~ < lane 16 {
            : u64 idx ? partitioned | << part 6 & + group lane 63 & + group lane 255
            : u64 c . ctrl idx
            ? == c 0 {
                = . ctrl idx fp
                = . keys idx key
                = . vals idx val
                ^
            } {}
            ? & == c fp == . keys idx key {
                = . vals idx val
                ^
            } {}
            = lane + lane 1
        }
        = group ? partitioned & + group 16 63 & + group 16 255
        = round + round 1
    }

    : ~ u64 idx ? partitioned | << part 6 & key 63 & key 255
    : i limit ? partitioned 64 256
    : ~ i step 0
    ~ < step limit {
        : u64 c . ctrl idx
        ? | == c 0 & == c fp == . keys idx key {
            = . ctrl idx fp
            = . keys idx key
            = . vals idx val
            ^
        } {}
        = idx ? partitioned | << part 6 & + idx 1 63 & + idx 1 255
        = step + step 1
    }
}

// Returns 1 and writes the payload to `out[0]` on a hit, 0 on a miss.
// An empty control slot ends the scan — the same early-out the peers use.
@ grouped_probe * u64 ctrl * u64 keys * u64 vals u64 probe_key b partitioned * u64 out → i {
    : u64 fp ( fp7 probe_key )
    : u64 part & >> probe_key 62 3
    : ~ u64 group ? partitioned & & probe_key 63 48 & & probe_key 255 240
    : i rounds ? partitioned 4 16

    : ~ i round 0
    ~ < round rounds {
        : ~ u64 lane 0
        ~ < lane 16 {
            : u64 idx ? partitioned | << part 6 & + group lane 63 & + group lane 255
            : u64 c . ctrl idx
            ? == c 0 { ^ 0 } {}
            ? & == c fp == . keys idx probe_key {
                = . out 0 . vals idx
                ^ 1
            } {}
            = lane + lane 1
        }
        = group ? partitioned & + group 16 63 & + group 16 255
        = round + round 1
    }

    ^ 0
}

@ zero_block * u64 p i n → v {
    : ~ i k 0
    ~ < k n {
        = . p k # u64 0
        = k + k 1
    }
}

@ main → i {
    : i cap 256
    : i bloom_words 64
    : i compact_chunk 64

    : *u64 st # *u64 ( malloc 8 )
    = . st 0 # u64 123456789
    : *u64 ctrl # *u64 ( malloc * cap 8 )
    : *u64 keys # *u64 ( malloc * cap 8 )
    : *u64 vals # *u64 ( malloc * cap 8 )
    : *u64 reducer_bloom # *u64 ( malloc * bloom_words 8 )
    : *u64 compact # *u64 ( malloc * compact_chunk 8 )
    : *u64 out # *u64 ( malloc 8 )
    ( zero_block ctrl cap )
    ( zero_block keys cap )
    ( zero_block vals cap )
    ( zero_block reducer_bloom bloom_words )
    ( zero_block compact compact_chunk )
    = . out 0 # u64 0

    : u64 build_rows 160
    : u64 total_queries 500000
    : b use_partitioned & >= build_rows 128 >= total_queries 200000

    : ~ u64 row 0
    ~ < row build_rows {
        : u64 key_high ( lcg_step st )
        : u64 key_low ( lcg_step st )
        : u64 key | << key_high 32 key_low
        : u64 val_high ( lcg_step st )
        : u64 val_low ( lcg_step st )
        : u64 val | << val_high 32 val_low
        ( bloom_add reducer_bloom key )
        ( grouped_insert ctrl keys vals key val use_partitioned )
        = row + row 1
    }

    : ~ u64 sum 0
    : ~ i compact_len 0
    : ~ u64 query 0
    ~ < query total_queries {
        : u64 probe_high ( lcg_step st )
        : u64 probe_low ( lcg_step st )
        : u64 probe_key | << probe_high 32 probe_low

        ? ( bloom_maybe reducer_bloom probe_key ) {
            ? == 1 ( grouped_probe ctrl keys vals probe_key use_partitioned out ) {
                = . compact compact_len . out 0
                = compact_len + compact_len 1
                ? == compact_len compact_chunk {
                    : ~ i j 0
                    ~ < j compact_chunk {
                        = sum ^^ sum . compact j
                        = j + j 1
                    }
                    = compact_len 0
                } {}
            } {}
        } {}

        = query + query 1
    }

    : ~ i tail 0
    ~ < tail compact_len {
        = sum ^^ sum . compact tail
        = tail + tail 1
    }

    ( free out )
    ( free compact )
    ( free reducer_bloom )
    ( free vals )
    ( free keys )
    ( free ctrl )
    ( free st )
    ^ ( finish sum )
}
