// benchmark-contract: safe-record-array;records=4096;record=4xu64(key,val,hits,tag);steps=10000000;lcg=mmix(seed=1);draw=state>>33;ia=r&4095;ib=(r>>12)&4095;swap=(r>>24)&1;fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// safe_record_array — 10M updates of a Vec of 4096 small records (four
// u64 fields, 32 bytes each, 128 KB: L2-resident). Each step draws two
// record indices from an MMIX LCG, reads both records BY VALUE, passes
// them to `mix`, which returns a two-field `Pair` by value, passes the
// first record and the pair to `bump`, which returns a new record by
// value, and stores that record back; on half the steps (bit 24 of the
// draw) it then exchanges the two records by value. The fold at the end
// reads every field of every record.
//
// What this row adds: aggregate layout, field access, a struct's
// by-value parameter and return path, and moving whole records in and
// out of a growable container — all through the SAFE surface (`vec_at`
// / `vec_put`, bounds-checked, no `unsafe`, no raw pointer), which is
// how ordinary NURL code holds records. `nbody`, the other record-ish
// row, is an `unsafe` struct-of-arrays over raw blocks.
//
// The C peer is an array of structs passed and returned by value; the
// Rust peer a `Vec<Rec>` of a `Copy` struct with bounds-checked
// indexing. All three back ends may inline `mix` and `bump` (nothing in
// any of the three asks them not to), so after optimisation the row
// measures the record traffic, not a call sequence.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

$ `stdlib/core/vec.nu`

: Rec { u64 key u64 val u64 hits u64 tag }

: Pair { u64 lo u64 hi }

@ mix Rec a Rec b u64 r → Pair {
    ^ @ Pair { ^^ ^^ . a key . b val r * + . a val . b key 2654435761 }
}

@ bump Rec a Pair p → Rec {
    ^ @ Rec { ^^ . a key . p lo + . a val >> . p hi 3 + . a hits 1 & + . a tag & . p lo 15 255 }
}

@ fnv u64 h u64 v → u64 { ^ * ^^ h v 1099511628211 }

@ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : u64 steps * 10000000 BENCH_SCALE
    : i n 4096

    : ( Vec Rec ) recs ( vec_with_cap [Rec] n )
    : ~ i z 0
    ~ < z n {
        : u64 zu # u64 z
        ( vec_push [Rec] recs @ Rec { * zu 2654435761 zu 0 & zu 7 } )
        = z + z 1
    }

    : ~ u64 x 1
    : ~ u64 k 0
    ~ < k steps {
        = x + * x 6364136223846793005 1442695040888963407
        : u64 r >> x 33
        : i ia # i & r 4095
        : i ib # i & >> r 12 4095
        : Rec a ( vec_at [Rec] recs ia )
        : Rec b ( vec_at [Rec] recs ib )
        : Pair p ( mix a b r )
        ( vec_put [Rec] recs ia ( bump a p ) )
        ? == & >> r 24 1 1 {
            : Rec t ( vec_at [Rec] recs ia )
            : Rec w ( vec_at [Rec] recs ib )
            ( vec_put [Rec] recs ia w )
            ( vec_put [Rec] recs ib t )
        } {}
        = k + k 1
    }

    : ~ u64 h 1469598103934665603
    : ~ i q 0
    ~ < q n {
        : Rec e ( vec_at [Rec] recs q )
        = h ( fnv h . e key )
        = h ( fnv h . e val )
        = h ( fnv h . e hits )
        = h ( fnv h . e tag )
        = q + q 1
    }
    = h ( fnv h x )
    ( nurl_println_int # i & h 0x7fffffffffffffff )
    ^ 0
}
