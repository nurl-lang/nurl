// The IFMA tier: nurl_v256_madd52lo / _hi, the radix-2^52 multiply-
// accumulate (VPMADD52LUQ / VPMADD52HUQ on a ymm register), and the
// generic nurl_v256_shrlane64 the Montgomery multiply moves its
// accumulator with.
//
// Each lane against the scalar product of nurl_mac: the 104-bit product
// of the operands' low 52 bits, its low 52 bits (lo) or the 52 above
// them (hi) added to the accumulator lane, mod 2^64. Operands are
// pseudorandom from a fixed seed with the top 12 bits set on purpose
// (the instruction ignores them) and all-ones lanes mixed in (the
// widest product, 2^104 − 2^53 + 1, and accumulators that wrap).
//
// requires: cpu-ifma
//
// The golden assumes a CPU with the tier: without it the gate in the
// first tier function panics.

: ~ u64 g_rng 0x2545f4914f6cdd1d

@ rnd → u64 {
    = g_rng ^^ g_rng << g_rng 13
    = g_rng ^^ g_rng >> g_rng 7
    = g_rng ^^ g_rng << g_rng 17
    ^ g_rng
}

@ word i t → u64 { ^ ? == % t 5 0 # u64 - 0 1 ( rnd ) }

// acc + (the low or high 52 bits of lo52(a)·lo52(b)).
@ ref u64 acc u64 a u64 b b high → u64 {
    : u64 m - << # u64 1 52 1
    : u64 x & a m
    : u64 y & b m
    : u64 lo ( nurl_mac_lo x y 0 0 )
    : u64 hi ( nurl_mac_hi x y 0 0 )
    ? high { ^ + acc | << hi 12 >> lo 52 } {}
    ^ + acc & lo m
}

@ madd v256 c v256 a v256 b b high → v256 {
    ? high { ^ ( nurl_v256_madd52hi c a b ) } {}
    ^ ( nurl_v256_madd52lo c a b )
}

@ main → i {
    : ~ i bad 0
    : ~ u64 sum 0
    : ~ i t 0
    ~ < t 400 {
        : u64 c0 ( word t ) : u64 c1 ( word + t 1 ) : u64 c2 ( rnd ) : u64 c3 ( rnd )
        : u64 a0 ( word + t 2 ) : u64 a1 ( rnd ) : u64 a2 ( word t ) : u64 a3 ( rnd )
        : u64 b0 ( rnd ) : u64 b1 ( word + t 3 ) : u64 b2 ( word t ) : u64 b3 ( rnd )
        : v256 c ( nurl_v256_set64 c0 c1 c2 c3 )
        : v256 a ( nurl_v256_set64 a0 a1 a2 a3 )
        : v256 b ( nurl_v256_set64 b0 b1 b2 b3 )
        : b high == % t 2 1
        : v256 r ( madd c a b high )
        : u64 r0 ( nurl_v256_get64 r 0 ) : u64 r1 ( nurl_v256_get64 r 1 )
        : u64 r2 ( nurl_v256_get64 r 2 ) : u64 r3 ( nurl_v256_get64 r 3 )
        ? != r0 ( ref c0 a0 b0 high ) { = bad + bad 1 } {}
        ? != r1 ( ref c1 a1 b1 high ) { = bad + bad 1 } {}
        ? != r2 ( ref c2 a2 b2 high ) { = bad + bad 1 } {}
        ? != r3 ( ref c3 a3 b3 high ) { = bad + bad 1 } {}
        = sum + * sum 31 ^^ ^^ r0 r1 ^^ r2 r3
        // shrlane64: a's lanes 1..3, then b's lane 0
        : v256 s ( nurl_v256_shrlane64 a b )
        ? | | != ( nurl_v256_get64 s 0 ) a1 != ( nurl_v256_get64 s 1 ) a2 | != ( nurl_v256_get64 s 2 ) a3 != ( nurl_v256_get64 s 3 ) b0 { = bad + bad 1 } {}
        = t + t 1
    }
    ( nurl_print `lanes: 1600, mismatches: ` ) ( nurl_print_int bad ) ( nurl_print `\n` )
    ( nurl_print `checksum: ` ) ( nurl_print_int # i sum ) ( nurl_print `\n` )
    ^ 0
}
