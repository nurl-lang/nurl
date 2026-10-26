// p256_comb_agree.nu — the fixed-base comb (p256ct_scalarmult_base: Booth
// digits, 52 per-window tables, no doublings) against the variable-base
// ladder (p256ct_scalarmult over G: 4-bit windows, doublings, a table
// built per call). Two independent code paths over the same field; 500
// pseudorandom scalars of 1 to 40 bytes, so the reduction mod n before
// the Booth recode is exercised on every length, must give the same
// 64-byte X‖Y.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ecdsa_p256.nu`

: ~ u64 g_s 0x243F6A8885A308D3

@ rnd → u64 {
    = g_s ^^ g_s << g_s 13
    = g_s ^^ g_s >> g_s 7
    = g_s ^^ g_s << g_s 17
    ^ g_s
}

@ main → i {
    : ( Vec i ) gx ( _p256_gx_plain )
    : ( Vec i ) gy ( _p256_gy_plain )
    : ~ i same 0
    : ~ i t 0
    ~ < t 500 {
        : i len + 1 # i % ( rnd ) 40
        : ( Vec u ) k ( vec_zeroed [u] len )
        : ~ i j 0
        ~ < j len { ( vec_put [u] k j # u & # i ( rnd ) 255 ) = j + j 1 }
        : ( Vec u ) a ( p256ct_scalarmult_base k )
        : ( Vec u ) b ( p256ct_scalarmult k gx gy )
        ? ( bytes_eq a b ) { = same + same 1 } {
            ( nurl_print `MISMATCH len=` ) ( nurl_print_int len ) ( nurl_print `\n` )
        }
        = t + t 1
    }
    ( nurl_print `comb == ladder: ` ) ( nurl_print_int same ) ( nurl_print `/500\n` )
    ^ ? == same 500 0 1
}
