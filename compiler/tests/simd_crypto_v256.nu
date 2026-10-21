// The VAES tier: nurl_v256_aes* and nurl_v256_clmul_*, two blocks per
// instruction.
//
// Each primitive is checked lane by lane against an answer from outside
// the tier under test: AES-128 against FIPS-197 Appendix C.1 in one lane
// and the v128 AES-NI primitives (simd_crypto.nu's subject) in the
// other, encrypting and decrypting; the carry-less products against the
// v128 products of each lane's halves. The functions are of every kind
// that reaches the tier by its own path in nurlc: a plain helper whose
// signature carries a v256 and is called from baseline code — the
// pointer crossing of emit_vabi, since a v256 is a ymm register only
// on the tier's side of the call — a `simd @` function (emitted once,
// for the tier), and a closure.
//
// requires: cpu-vaes
//
// The golden assumes a CPU with the VAES tier: without it the gate in
// the first VAES function panics.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

unsafe @ ld ( Vec u ) b → v128 { ^ ( nurl_v128_ld # s ( vec_data [u] b ) ) }

unsafe @ hex_of v128 x → String {
    : ( Vec u ) b ( vec_zeroed [u] 16 )
    ( nurl_v128_st # s ( vec_data [u] b ) x )
    ^ ( bytes_to_hex b )
}

@ show s label v128 x → v {
    : String h ( hex_of x )
    ( nurl_print label ) ( nurl_print ( string_data h ) ) ( nurl_print `\n` )
}

// Both lanes of a v256, low first.
@ show2 s label v256 x → v {
    ( show label ( nurl_v256_lo128 x ) )
    ( show `           ` ( nurl_v256_hi128 x ) )
}

// The AES-128 key schedule on the v128 tier (as simd_crypto.nu builds
// it), each round key stored twice over — the ymm operand of a round.
@ next_key v128 k i rcon → v128 {
    : i w3 # i ( nurl_v128_get32 k 3 )
    : v128 t ( nurl_v128_aesenclast ( nurl_v128_bcast32 ( nurl_rotr32 w3 8 ) ) ( nurl_v128_bcast32 rcon ) )
    : i w4 ^^ # i ( nurl_v128_get32 k 0 ) # i ( nurl_v128_get32 t 0 )
    : i w5 ^^ # i ( nurl_v128_get32 k 1 ) w4
    : i w6 ^^ # i ( nurl_v128_get32 k 2 ) w5
    : i w7 ^^ w3 w6
    ^ ( nurl_v128_set32 w4 w5 w6 w7 )
}

unsafe @ schedule2 ( Vec u ) key → ( Vec u ) {
    : ( Vec u ) rk ( vec_zeroed [u] 352 )
    : *u p ( vec_data [u] rk )
    : ( Vec u ) rcon ( hx `01020408102040801b36` )
    : ~ v128 k ( ld key )
    : ~ i r 0
    ~ <= r 10 {
        ? > r 0 { = k ( next_key k # i ( vec_at [u] rcon - r 1 ) ) } {}
        ( nurl_v256_st # s + # i p * r 32 ( nurl_v256_join128 k k ) )
        = r + r 1
    }
    ^ rk
}

// Two blocks through the cipher: a VAES helper with a v256 signature,
// called below from `main`, which is baseline code.
unsafe @ encrypt2 * u rk2 v256 pt → v256 {
    : ~ v256 b ( nurl_v256_xor pt ( nurl_v256_ld # s rk2 ) )
    : ~ i r 1
    ~ < r 10 { = b ( nurl_v256_aesenc b ( nurl_v256_ld # s + # i rk2 * r 32 ) ) = r + r 1 }
    ^ ( nurl_v256_aesenclast b ( nurl_v256_ld # s + # i rk2 320 ) )
}

// One round, as a VAES helper: its `.tier` copy is what encrypt2x calls.
@ round2 v256 b v256 k → v256 { ^ ( nurl_v256_aesenc b k ) }

// The same as a `simd @` function: it reaches the VAES tier through
// round2, so it is emitted once, for the tier.
unsafe simd @ encrypt2x * u rk2 v256 pt → v256 {
    : ~ v256 b ( nurl_v256_xor pt ( nurl_v256_ld # s rk2 ) )
    : ~ i r 1
    ~ < r 10 { = b ( round2 b ( nurl_v256_ld # s + # i rk2 * r 32 ) ) = r + r 1 }
    ^ ( nurl_v256_aesenclast b ( nurl_v256_ld # s + # i rk2 320 ) )
}

// Back again, the Equivalent Inverse Cipher: the round keys through the
// v128 tier's InvMixColumns, two lanes a round.
unsafe @ decrypt2 * u rk2 v256 ct → v256 {
    : ~ v256 b ( nurl_v256_xor ct ( nurl_v256_ld # s + # i rk2 320 ) )
    : ~ i r 9
    ~ >= r 1 {
        : v128 k ( nurl_v128_aesimc ( nurl_v128_ld # s + # i rk2 * r 32 ) )
        = b ( nurl_v256_aesdec b ( nurl_v256_join128 k k ) )
        = r - r 1
    }
    ^ ( nurl_v256_aesdeclast b ( nurl_v256_ld # s rk2 ) )
}

// The v128 cipher on one block, the second lane's answer.
unsafe @ encrypt1 * u rk2 v128 pt → v128 {
    : ~ v128 b ( nurl_v128_xor pt ( nurl_v128_ld # s rk2 ) )
    : ~ i r 1
    ~ < r 10 { = b ( nurl_v128_aesenc b ( nurl_v128_ld # s + # i rk2 * r 32 ) ) = r + r 1 }
    ^ ( nurl_v128_aesenclast b ( nurl_v128_ld # s + # i rk2 320 ) )
}

@ same v128 a v128 b → b { ^ & == ( nurl_v128_get64 a 0 ) ( nurl_v128_get64 b 0 ) == ( nurl_v128_get64 a 1 ) ( nurl_v128_get64 b 1 ) }

// The four products of two lanes: lane 0 as simd_crypto.nu has it (so
// the same answers), lane 1 other halves. Each lane must be what the
// v128 product of its own halves is.
@ products → v {
    : v128 a0 ( nurl_v128_set64 0x87 0xff )
    : v128 b0 ( nurl_v128_set64 3 0x8000000000000000 )
    : v128 a1 ( nurl_v128_set64 0x1234567890abcdef 0x5 )
    : v128 b1 ( nurl_v128_set64 0xfedcba0987654321 0x3 )
    : v256 a ( nurl_v256_join128 a0 a1 )
    : v256 b ( nurl_v256_join128 b0 b1 )
    ( show2 `clmul ll   ` ( nurl_v256_clmul_ll a b ) )
    ( show2 `clmul hl   ` ( nurl_v256_clmul_hl a b ) )
    ( show2 `clmul lh   ` ( nurl_v256_clmul_lh a b ) )
    ( show2 `clmul hh   ` ( nurl_v256_clmul_hh a b ) )
    : b ok & & & ( same ( nurl_v256_hi128 ( nurl_v256_clmul_ll a b ) ) ( nurl_v128_clmul_ll a1 b1 ) )
    ( same ( nurl_v256_hi128 ( nurl_v256_clmul_hl a b ) ) ( nurl_v128_clmul_hl a1 b1 ) )
    ( same ( nurl_v256_hi128 ( nurl_v256_clmul_lh a b ) ) ( nurl_v128_clmul_lh a1 b1 ) )
    ( same ( nurl_v256_hi128 ( nurl_v256_clmul_hh a b ) ) ( nurl_v128_clmul_hh a1 b1 ) )
    ( nurl_print ? ok `lane 1 products agree with v128\n` `lane 1 products DIFFER from v128\n` )
}

unsafe @ main → i {
    ? ! ( nurl_cpu_has_vaes ) { ( nurl_print `no VAES tier on this CPU\n` ) ^ 1 } {}

    : ( Vec u ) key ( hx `000102030405060708090a0b0c0d0e0f` )
    : ( Vec u ) rk ( schedule2 key )
    : *u rkp ( vec_data [u] rk )
    // Lane 0 FIPS-197 C.1's plaintext, lane 1 another block.
    : v128 p0 ( ld ( hx `00112233445566778899aabbccddeeff` ) )
    : v128 p1 ( ld ( hx `0f1e2d3c4b5a69788796a5b4c3d2e1f0` ) )
    : v256 pt ( nurl_v256_join128 p0 p1 )
    : v256 ct ( encrypt2 rkp pt )
    ( show2 `ciphertext ` ct )
    ( nurl_print ? ( same ( nurl_v256_hi128 ct ) ( encrypt1 rkp p1 ) ) `lane 1 agrees with v128\n` `lane 1 DIFFERS from v128\n` )
    : v256 ct2 ( encrypt2x rkp pt )
    ( nurl_print ? & ( same ( nurl_v256_lo128 ct2 ) ( nurl_v256_lo128 ct ) ) ( same ( nurl_v256_hi128 ct2 ) ( nurl_v256_hi128 ct ) ) `simd clone agrees\n` `simd clone DIFFERS\n` )
    ( show2 `decrypted  ` ( decrypt2 rkp ct ) )

    ( products )

    // A closure body is its own function, in the tier by its own use.
    : ( @ v256 v256 ) sq \ v256 x → v256 { ^ ( nurl_v256_clmul_ll x x ) }
    ( show2 `closure sq ` ( sq ( nurl_v256_join128 ( nurl_v128_set64 0x87 0 ) ( nurl_v128_set64 0x3 0 ) ) ) )

    // The portable halves helpers the tier is written with.
    ( show2 `bswap128   ` ( nurl_v256_bswap128 ( nurl_v256_join128 p0 p1 ) ) )
    ^ 0
}
