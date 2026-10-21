// A v256 or v512 crossing a call between functions compiled for
// different feature sets.
//
// A `<4 x i64>` travels in one ymm register when a function has AVX and
// in two xmm registers when it has not; a `<8 x i64>` in one zmm, two
// ymm or four xmm. A `simd @` function's clones are each compiled for
// their own feature set while its dispatcher and every caller are
// compiled for theirs, so before emit_vabi a `simd` function taking two
// v256s answered garbage on every AVX2 machine: the baseline dispatcher
// handed the x86-64-v3 clone its arguments in the wrong registers (the
// sum below came back 301 where 101 is right). Now the clones take
// their wide vectors by pointer and the dispatcher, inlined into each
// caller, spills them.
//
// The values come from the argument count so nothing folds at compile
// time; the calls are made from baseline code (`main`) and from another
// `simd` function's clones, which have AVX on an AVX2 machine and not
// otherwise — every pairing a CPU can produce, on whichever CPU runs
// this. crypto_tier_ir.sh runs it with the wide clone taken away too.

// Sum of b, a hundred times over, onto a: a loop so the clone is not
// inlined back into its dispatcher's caller.
simd @ addn v256 a v256 b → v256 {
    : ~ v256 x a
    : ~ i k 0
    ~ < k 100 { = x ( nurl_v256_add32 x b ) = k + k 1 }
    ^ x
}

simd @ addn512 v512 a v512 b → v512 {
    : ~ v512 x a
    : ~ i k 0
    ~ < k 100 { = x ( nurl_v512_add64 x b ) = k + k 1 }
    ^ x
}

// Takes a v256 but returns a scalar, and calls addn from its own clones.
simd @ lane_sum v256 a i n → u64 {
    : v256 y ( addn a a )
    ^ + + + + ( nurl_v256_get64 y 0 ) ( nurl_v256_get64 y 1 ) ( nurl_v256_get64 y 2 ) ( nurl_v256_get64 y 3 ) # u64 n
}

@ main → i {
    : i n ( nurl_argc )
    : v256 x ( nurl_v256_set64 n 2 3 4 )
    : v256 y ( addn x x )
    ( nurl_println_int # i ( nurl_v256_get64 y 0 ) )
    ( nurl_println_int # i ( nurl_v256_get64 y 3 ) )
    ( nurl_println_int # i ( lane_sum x n ) )
    : v512 z ( nurl_v512_join256 x ( nurl_v256_set64 5 6 7 8 ) )
    : v512 w ( addn512 z z )
    ( nurl_println_int # i ( nurl_v256_get64 ( nurl_v512_lo256 w ) 0 ) )
    ( nurl_println_int # i ( nurl_v256_get64 ( nurl_v512_hi256 w ) 3 ) )
    ^ 0
}
