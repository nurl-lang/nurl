// x25519_base_agree.nu — the fixed-base public key (x25519_base: ref10's
// signed radix-16 digits over an Edwards table, then the birational map)
// against the Montgomery ladder at u = 9, for 300 scalars: seven chosen
// to walk the digit recoding's edges — all-zero, all-0xff, all-0x88 and
// all-0x77 (every digit ±8, every carry taken or none), 0x80 and 0x08
// bytes, the largest clamped scalar — then generated ones. The two share
// no code above the field, so agreement checks the table, the digit
// signs and the map; the chained SHA-256 of the ladder's answers is the
// golden, computed from RFC 7748's pseudocode in Python big integers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/x25519.nu`

@ fill i byte → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 32 )
    : ~ i q 0
    ~ < q 32 { ( vec_push [u] v # u byte ) = q + q 1 }
    ^ v
}

// byte q = ((i·131 + q·71 + q²·7 + 11) xor i·29) & 255
@ gen32 i i → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 32 )
    : ~ i q 0
    ~ < q 32 { ( vec_push [u] v # u & ^^ + + + * i 131 * q 71 * * q q 7 11 * i 29 255 ) = q + q 1 }
    ^ v
}

@ main → i {
    : ( Vec ( Vec u ) ) ks ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] ks ( fill 0 ) )
    ( vec_push [( Vec u )] ks ( fill 255 ) )
    ( vec_push [( Vec u )] ks ( fill 136 ) )
    ( vec_push [( Vec u )] ks ( fill 119 ) )
    ( vec_push [( Vec u )] ks ( fill 128 ) )
    ( vec_push [( Vec u )] ks ( fill 8 ) )
    : ( Vec u ) top ( fill 255 )
    ( vec_set [u] top 0 # u 248 )
    ( vec_set [u] top 31 # u 127 )
    ( vec_push [( Vec u )] ks top )
    : ( Vec u ) nine ( vec_zeroed [u] 32 )
    ( vec_set [u] nine 0 # u 9 )
    : ~ ( Vec u ) acc ( vec_zeroed [u] 32 )
    : ~ i bad 0
    : ~ i i 0
    ~ < i 300 {
        : ( Vec u ) k ? < i 7 ?? ( vec_get [( Vec u )] ks i ) { T x → x F _ → ( fill 0 ) } ( gen32 i )
        : ( Vec u ) vialadder ( x25519 k nine )
        ? ! ( bytes_eq ( x25519_base k ) vialadder ) {
            ( nurl_print `disagree at ` ) ( nurl_print_int i ) ( nurl_print `\n` )
            = bad + bad 1
        } {}
        : ( Vec u ) both ( vec_with_cap [u] 64 )
        ( bytes_extend_bytes both acc )
        ( bytes_extend_bytes both vialadder )
        = acc ( sha256_pure both )
        = i + i 1
    }
    ( nurl_print `base vs ladder: 300 scalars, ` ) ( nurl_print_int bad ) ( nurl_print ` disagree\n` )
    : String h ( bytes_to_hex acc )
    ( nurl_print `chain ` ) ( nurl_print ( string_data h ) ) ( nurl_print `\n` )
    ( string_free h )
    ^ ? == bad 0 0 1
}
