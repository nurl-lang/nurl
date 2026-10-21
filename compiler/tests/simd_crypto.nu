// The hardware crypto tier: nurl_v128_aes* and nurl_v128_clmul_*.
//
// Each primitive is checked against a value from outside this file:
// AES-128 against FIPS-197 Appendix C.1 (key 000102…0f, plaintext
// 00112233…ff → 69c4e0d8…c55a) through a key schedule built on
// `aesenclast` and back through `aesimc` + `aesdec`; the carry-less
// products against hand-worked GF(2)[x] arithmetic. The schedule, the
// cipher and the products live in three different kinds of function —
// a plain helper, a `simd @` function and a closure — because each one
// reaches the crypto tier by a different path in nurlc (__crypto_fn_ir,
// emit_multiversion, the deferred closure definitions) and a path that
// forgot the tier would not compile, or would SIGILL.
//
// requires: cpu-aes
//
// The golden assumes a CPU with the tier, as every CI runner has:
// without it the gate in the first crypto function panics.

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

// One AES-128 key-schedule step: the next round key from the previous
// one. SubWord(RotWord(w3)) ^ rcon comes from `aesenclast` on w3
// rotated and broadcast to all four columns — ShiftRows is the identity
// on a state whose columns are equal — and the rest is the schedule's
// running XOR, in scalars.
@ next_key v128 k i rcon → v128 {
    : i w3 # i ( nurl_v128_get32 k 3 )
    : v128 t ( nurl_v128_aesenclast ( nurl_v128_bcast32 ( nurl_rotr32 w3 8 ) ) ( nurl_v128_bcast32 rcon ) )
    : i s # i ( nurl_v128_get32 t 0 )
    : i w4 ^^ # i ( nurl_v128_get32 k 0 ) s
    : i w5 ^^ # i ( nurl_v128_get32 k 1 ) w4
    : i w6 ^^ # i ( nurl_v128_get32 k 2 ) w5
    : i w7 ^^ w3 w6
    ^ ( nurl_v128_set32 w4 w5 w6 w7 )
}

// The eleven round keys, stored consecutively.
unsafe @ schedule ( Vec u ) key → ( Vec u ) {
    : ( Vec u ) rk ( vec_zeroed [u] 176 )
    : *u p ( vec_data [u] rk )
    : ( Vec u ) rcon ( hx `01020408102040801b36` )
    : ~ v128 k ( ld key )
    ( nurl_v128_st # s p k )
    : ~ i r 1
    ~ <= r 10 {
        = k ( next_key k # i ( vec_at [u] rcon - r 1 ) )
        ( nurl_v128_st # s + # i p * r 16 k )
        = r + r 1
    }
    ^ rk
}

// One round, as a helper: a tier function with a v128 signature, so it
// gets an inline copy (`aes_round.tier`) that tier callers use.
@ aes_round v128 b v128 k → v128 { ^ ( nurl_v128_aesenc b k ) }

// Encrypt one block: a `simd @` function, so it is cloned for the tier.
unsafe simd @ encrypt * u rk v128 pt → v128 {
    : ~ v128 b ( nurl_v128_xor pt ( nurl_v128_ld # s rk ) )
    : ~ i r 1
    ~ < r 10 { = b ( aes_round b ( nurl_v128_ld # s + # i rk * r 16 ) ) = r + r 1 }
    ^ ( nurl_v128_aesenclast b ( nurl_v128_ld # s + # i rk 160 ) )
}

// Decrypt it again with the Equivalent Inverse Cipher: the middle round
// keys through InvMixColumns, applied in reverse order.
unsafe @ decrypt * u rk v128 ct → v128 {
    : ~ v128 b ( nurl_v128_xor ct ( nurl_v128_ld # s + # i rk 160 ) )
    : ~ i r 9
    ~ >= r 1 {
        = b ( nurl_v128_aesdec b ( nurl_v128_aesimc ( nurl_v128_ld # s + # i rk * r 16 ) ) )
        = r - r 1
    }
    ^ ( nurl_v128_aesdeclast b ( nurl_v128_ld # s rk ) )
}

// The carry-less products. A function of their own: `main` uses no
// primitive, so it stays baseline and its nurl_cpu_has_aes question is
// reachable on a CPU without the tier — a function that uses one is
// gated at its entry, before its first line runs.
// 0x87 · 0x3 = 0x87 ^ 0x10e = 0x189 (no carry from bit 0 into 1).
// a = (lo 0x87, hi 0xff), b = (lo 0x3, hi 1 << 63): each product picks
// its halves, and the high one is 0xff · 2^63 = 0x7f80 << 64.
@ products → v {
    : v128 a ( nurl_v128_set64 0x87 0xff )
    : v128 b ( nurl_v128_set64 3 0x8000000000000000 )
    ( show `clmul ll     ` ( nurl_v128_clmul_ll a b ) )
    ( show `clmul hl     ` ( nurl_v128_clmul_hl a b ) )
    ( show `clmul lh     ` ( nurl_v128_clmul_lh a b ) )
    ( show `clmul hh     ` ( nurl_v128_clmul_hh a b ) )
}

unsafe @ main → i {
    ? ! ( nurl_cpu_has_aes ) { ( nurl_print `no crypto tier on this CPU\n` ) ^ 1 } {}

    // ── FIPS-197 C.1 ──────────────────────────────────────────────
    : ( Vec u ) key ( hx `000102030405060708090a0b0c0d0e0f` )
    : ( Vec u ) rk ( schedule key )
    : *u rkp ( vec_data [u] rk )
    // The last round key: FIPS-197 C.1's round[10].k_sch.
    ( show `round key 10 ` ( nurl_v128_ld # s + # i rkp 160 ) )
    : v128 pt ( ld ( hx `00112233445566778899aabbccddeeff` ) )
    : v128 ct ( encrypt rkp pt )
    ( show `ciphertext   ` ct )
    ( show `decrypted    ` ( decrypt rkp ct ) )

    ( products )

    // A closure body is its own function: it reaches the tier through
    // the deferred closure definitions.
    : v128 m ( nurl_v128_set64 0x87 0 )
    : ( @ v128 v128 ) sq \ v128 x → v128 { ^ ( nurl_v128_clmul_ll x x ) }
    // Squaring is linear in GF(2): 0x87² spreads the bits apart.
    ( show `closure sq   ` ( sq m ) )

    // bswap128 is portable, not tier: but it is GHASH's other half.
    ( show `bswap128     ` ( nurl_v128_bswap128 ( ld ( hx `000102030405060708090a0b0c0d0e0f` ) ) ) )
    ^ 0
}
