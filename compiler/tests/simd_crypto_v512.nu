// The AVX-512 VAES tier: nurl_v512_aes* and nurl_v512_clmul_*, four
// blocks per instruction — and the v512 type they are written on.
//
// As simd_crypto_v256.nu, one register wider: AES-128 against FIPS-197
// Appendix C.1 in lane 0 and the v128 AES-NI primitives in lanes 1..3,
// encrypting and decrypting; the products against the v128 products of
// each lane's halves; a plain helper with a v512 signature called from
// baseline code (a zmm register only on the tier's side of the call:
// emit_vabi's pointer crossing), a `simd @` function and a closure.
//
// requires: cpu-vaes512
//
// The golden assumes a CPU with the tier: without it the gate in the
// first tier function panics.

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

@ lane v512 x i k → v128 {
    : v256 h ? < k 2 ( nurl_v512_lo256 x ) ( nurl_v512_hi256 x )
    ? == 0 & k 1 { ^ ( nurl_v256_lo128 h ) } {}
    ^ ( nurl_v256_hi128 h )
}

// The four lanes of a v512, low first.
@ show4 s label v512 x → v {
    ( show label ( lane x 0 ) )
    ( show `           ` ( lane x 1 ) )
    ( show `           ` ( lane x 2 ) )
    ( show `           ` ( lane x 3 ) )
}

@ join4 v128 a v128 b v128 c v128 d → v512 { ^ ( nurl_v512_join256 ( nurl_v256_join128 a b ) ( nurl_v256_join128 c d ) ) }

@ same v128 a v128 b → b { ^ & == ( nurl_v128_get64 a 0 ) ( nurl_v128_get64 b 0 ) == ( nurl_v128_get64 a 1 ) ( nurl_v128_get64 b 1 ) }

// The AES-128 key schedule on the v128 tier: eleven round keys.
@ next_key v128 k i rcon → v128 {
    : i w3 # i ( nurl_v128_get32 k 3 )
    : v128 t ( nurl_v128_aesenclast ( nurl_v128_bcast32 ( nurl_rotr32 w3 8 ) ) ( nurl_v128_bcast32 rcon ) )
    : i w4 ^^ # i ( nurl_v128_get32 k 0 ) # i ( nurl_v128_get32 t 0 )
    : i w5 ^^ # i ( nurl_v128_get32 k 1 ) w4
    : i w6 ^^ # i ( nurl_v128_get32 k 2 ) w5
    : i w7 ^^ w3 w6
    ^ ( nurl_v128_set32 w4 w5 w6 w7 )
}

unsafe @ schedule ( Vec u ) key → ( Vec u ) {
    : ( Vec u ) rk ( vec_zeroed [u] 176 )
    : *u p ( vec_data [u] rk )
    : ( Vec u ) rcon ( hx `01020408102040801b36` )
    : ~ v128 k ( ld key )
    : ~ i r 0
    ~ <= r 10 {
        ? > r 0 { = k ( next_key k # i ( vec_at [u] rcon - r 1 ) ) } {}
        ( nurl_v128_st # s + # i p * r 16 k )
        = r + r 1
    }
    ^ rk
}

// Four blocks through the cipher, the round keys broadcast to every
// lane: a tier helper with a v512 signature, called from `main`.
unsafe @ encrypt4 * u rk v512 pt → v512 {
    : ~ v512 b ( nurl_v512_xor pt ( nurl_v512_bcast128 ( nurl_v128_ld # s rk ) ) )
    : ~ i r 1
    ~ < r 10 { = b ( nurl_v512_aesenc b ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk * r 16 ) ) ) = r + r 1 }
    ^ ( nurl_v512_aesenclast b ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk 160 ) ) )
}

// One round as a helper; encrypt4x calls its `.tier` copy.
@ round4 v512 b v512 k → v512 { ^ ( nurl_v512_aesenc b k ) }

unsafe simd @ encrypt4x * u rk v512 pt → v512 {
    : ~ v512 b ( nurl_v512_xor pt ( nurl_v512_bcast128 ( nurl_v128_ld # s rk ) ) )
    : ~ i r 1
    ~ < r 10 { = b ( round4 b ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk * r 16 ) ) ) = r + r 1 }
    ^ ( nurl_v512_aesenclast b ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk 160 ) ) )
}

unsafe @ decrypt4 * u rk v512 ct → v512 {
    : ~ v512 b ( nurl_v512_xor ct ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk 160 ) ) )
    : ~ i r 9
    ~ >= r 1 {
        = b ( nurl_v512_aesdec b ( nurl_v512_bcast128 ( nurl_v128_aesimc ( nurl_v128_ld # s + # i rk * r 16 ) ) ) )
        = r - r 1
    }
    ^ ( nurl_v512_aesdeclast b ( nurl_v512_bcast128 ( nurl_v128_ld # s rk ) ) )
}

unsafe @ encrypt1 * u rk v128 pt → v128 {
    : ~ v128 b ( nurl_v128_xor pt ( nurl_v128_ld # s rk ) )
    : ~ i r 1
    ~ < r 10 { = b ( nurl_v128_aesenc b ( nurl_v128_ld # s + # i rk * r 16 ) ) = r + r 1 }
    ^ ( nurl_v128_aesenclast b ( nurl_v128_ld # s + # i rk 160 ) )
}

@ products → v {
    : v128 a0 ( nurl_v128_set64 0x87 0xff )
    : v128 b0 ( nurl_v128_set64 3 0x8000000000000000 )
    : v128 a1 ( nurl_v128_set64 0x1234567890abcdef 0x5 )
    : v128 b1 ( nurl_v128_set64 0xfedcba0987654321 0x3 )
    : v128 a2 ( nurl_v128_set64 0xffffffffffffffff 0x8000000000000001 )
    : v128 b2 ( nurl_v128_set64 0xffffffffffffffff 0x8000000000000001 )
    : v128 a3 ( nurl_v128_set64 0 0x0123456789abcdef )
    : v128 b3 ( nurl_v128_set64 0x1111111111111111 0 )
    : v512 a ( join4 a0 a1 a2 a3 )
    : v512 b ( join4 b0 b1 b2 b3 )
    ( show4 `clmul ll   ` ( nurl_v512_clmul_ll a b ) )
    ( show4 `clmul hh   ` ( nurl_v512_clmul_hh a b ) )
    : ~ b ok T
    : ~ i k 0
    ~ < k 4 {
        : v128 ak ? == k 0 a0 ? == k 1 a1 ? == k 2 a2 a3
        : v128 bk ? == k 0 b0 ? == k 1 b1 ? == k 2 b2 b3
        = ok & ok & & & ( same ( lane ( nurl_v512_clmul_ll a b ) k ) ( nurl_v128_clmul_ll ak bk ) )
        ( same ( lane ( nurl_v512_clmul_hl a b ) k ) ( nurl_v128_clmul_hl ak bk ) )
        ( same ( lane ( nurl_v512_clmul_lh a b ) k ) ( nurl_v128_clmul_lh ak bk ) )
        ( same ( lane ( nurl_v512_clmul_hh a b ) k ) ( nurl_v128_clmul_hh ak bk ) )
        = k + k 1
    }
    ( nurl_print ? ok `every lane's products agree with v128\n` `a lane's products DIFFER from v128\n` )
}

unsafe @ main → i {
    ? ! ( nurl_cpu_has_vaes512 ) { ( nurl_print `no AVX-512 VAES tier on this CPU\n` ) ^ 1 } {}

    : ( Vec u ) key ( hx `000102030405060708090a0b0c0d0e0f` )
    : ( Vec u ) rk ( schedule key )
    : *u rkp ( vec_data [u] rk )
    : v128 p0 ( ld ( hx `00112233445566778899aabbccddeeff` ) )
    : v128 p1 ( ld ( hx `0f1e2d3c4b5a69788796a5b4c3d2e1f0` ) )
    : v128 p2 ( ld ( hx `ffffffffffffffffffffffffffffffff` ) )
    : v128 p3 ( ld ( hx `00000000000000000000000000000000` ) )
    : v512 pt ( join4 p0 p1 p2 p3 )
    : v512 ct ( encrypt4 rkp pt )
    ( show4 `ciphertext ` ct )
    : b agree & & ( same ( lane ct 1 ) ( encrypt1 rkp p1 ) ) ( same ( lane ct 2 ) ( encrypt1 rkp p2 ) ) ( same ( lane ct 3 ) ( encrypt1 rkp p3 ) )
    ( nurl_print ? agree `lanes 1..3 agree with v128\n` `a lane DIFFERS from v128\n` )
    : v512 ct2 ( encrypt4x rkp pt )
    : b same4 & & & ( same ( lane ct2 0 ) ( lane ct 0 ) ) ( same ( lane ct2 1 ) ( lane ct 1 ) ) ( same ( lane ct2 2 ) ( lane ct 2 ) ) ( same ( lane ct2 3 ) ( lane ct 3 ) )
    ( nurl_print ? same4 `simd clone agrees\n` `simd clone DIFFERS\n` )
    ( show4 `decrypted  ` ( decrypt4 rkp ct ) )

    ( products )

    : ( @ v512 v512 ) sq \ v512 x → v512 { ^ ( nurl_v512_clmul_ll x x ) }
    ( show4 `closure sq ` ( sq ( join4 ( nurl_v128_set64 0x87 0 ) ( nurl_v128_set64 0x3 0 ) ( nurl_v128_set64 0x5 0 ) ( nurl_v128_set64 0xff 0 ) ) ) )

    // The generic v512 helpers the tier is written with.
    ( show4 `bswap128   ` ( nurl_v512_bswap128 pt ) )
    ( show4 `add32      ` ( nurl_v512_add32 pt ( nurl_v512_bcast128 ( nurl_v128_set32 1 2 3 4 ) ) ) )
    ^ 0
}
