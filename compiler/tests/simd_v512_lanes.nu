// simd_v512_lanes.nu — v512's 32-bit group, the primitives sixteen-block
// ChaCha20 is written on: nurl_v512_bcast32, _rotl32, the in-lane
// interleaves _unpacklo32 / _unpackhi32 / _unpacklo64 / _unpackhi64 (per
// 128-bit lane, as v256's are per half) and the 128-bit lane shuffles
// _even128 / _odd128; and its 64-bit group, eight-lane Poly1305's:
// _bcast64, _mul32u (the low halves' product: a lane's high half must not
// reach it), _shl64 / _shr64 (the count masked to the lane). Lane by lane
// against answers worked out by hand.
//
// The same calls run twice: in a plain function, where v512 is legalised
// to narrower registers, and in a `simd v4` one, which is AVX-512 code
// on a CPU with x86-64-v4. Both must print the golden.

$ `stdlib/core/vec.nu`

// The sixteen 32-bit lanes of x, low first.
unsafe @ put s label v512 x → v {
    : ( Vec u ) b ( vec_zeroed [u] 64 )
    : *u p ( vec_data [u] b )
    ( nurl_v512_st # s p x )
    : *u32 w # *u32 p
    ( nurl_print label )
    : ~ i k 0
    ~ < k 16 { ( nurl_print ` ` ) ( nurl_print_int # i . w k ) = k + k 1 }
    ( nurl_print `\n` )
}

// The eight 64-bit lanes of x, low first.
unsafe @ put64 s label v512 x → v {
    : ( Vec u ) b ( vec_zeroed [u] 64 )
    : *u p ( vec_data [u] b )
    ( nurl_v512_st # s p x )
    : *i w # *i p
    ( nurl_print label )
    : ~ i k 0
    ~ < k 8 { ( nurl_print ` ` ) ( nurl_print_int . w k ) = k + k 1 }
    ( nurl_print `\n` )
}

// 0, 1, …, 15 in the sixteen lanes.
inline @ iota → v512 {
    ^ ( nurl_v512_join256
    ( nurl_v256_set64 4294967296 12884901890 21474836484 30064771078 )
    ( nurl_v256_set64 38654705672 47244640266 55834574860 64424509454 ) )
}

// `z` is 0 when the test runs, but the compiler cannot know it: without
// it every answer below would be folded at compile time and no
// instruction under test would run.
inline @ ops i z → v {
    : v512 a ( nurl_v512_add32 ( iota ) ( nurl_v512_bcast32 z ) )
    : v512 b ( nurl_v512_add32 a ( nurl_v512_bcast32 100 ) )
    : v512 x ( nurl_v512_bcast32 + 305419896 z )  // 0x12345678
    ( put `bcast32   ` ( nurl_v512_bcast32 + 7 z ) )
    ( put `rotl32 7  ` ( nurl_v512_rotl32 x 7 ) )
    ( put `rotl32 8  ` ( nurl_v512_rotl32 x 8 ) )
    ( put `rotl32 12 ` ( nurl_v512_rotl32 x 12 ) )
    ( put `rotl32 16 ` ( nurl_v512_rotl32 x 16 ) )
    ( put `rotl32 1  ` ( nurl_v512_rotl32 ( nurl_v512_bcast32 + 2147483649 z ) 1 ) )
    ( put `unpacklo32` ( nurl_v512_unpacklo32 a b ) )
    ( put `unpackhi32` ( nurl_v512_unpackhi32 a b ) )
    ( put `unpacklo64` ( nurl_v512_unpacklo64 a b ) )
    ( put `unpackhi64` ( nurl_v512_unpackhi64 a b ) )
    ( put `even128   ` ( nurl_v512_even128 a b ) )
    ( put `odd128    ` ( nurl_v512_odd128 a b ) )
    : v512 q ( nurl_v512_bcast64 + 4886718345 z )  // 0x123456789
    ( put64 `bcast64   ` q )
    // low halves 3, 2^32 − 1, 5, 2^32 − 1, 6 … 9 against 10, 2^32 − 1,
    // 11, 2, 1000 … 1003; the high halves (1, 0, 0, 7 / 0, 0, 1, 0) drop out
    : v512 mx ( nurl_v512_join256 ( nurl_v256_set64 + 4294967299 z 4294967295 5 34359738367 ) ( nurl_v256_set64 6 7 8 9 ) )
    : v512 my ( nurl_v512_join256 ( nurl_v256_set64 10 4294967295 + 4294967307 z 2 ) ( nurl_v256_set64 1000 1001 1002 1003 ) )
    ( put64 `mul32u    ` ( nurl_v512_mul32u mx my ) )
    ( put64 `shl64 12  ` ( nurl_v512_shl64 q 12 ) )
    ( put64 `shl64 68  ` ( nurl_v512_shl64 q + 68 z ) )
    ( put64 `shr64 8   ` ( nurl_v512_shr64 q 8 ) )
    ( put64 `shr64 63  ` ( nurl_v512_shr64 ( nurl_v512_bcast64 + + 1 << 1 63 z ) 63 ) )
}

// `ops` is always inlined, so this clone carries its own copy.
simd v4 @ ops4 i z → v { ( ops z ) }

@ main → i {
    : i z - ( nurl_argv_count ) 1
    ( ops z )
    ( nurl_print `-- simd v4\n` )
    ( ops4 z )
    ^ 0
}
