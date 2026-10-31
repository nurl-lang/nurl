// p256_comb_agree.nu — the fixed-base comb (p256ct_scalarmult_base: Booth
// digits, 52 per-window tables, no doublings) against the variable-base
// ladder (p256ct_scalarmult over G: signed 5-bit windows, doublings, a
// table built per call). Two independent code paths over the same field; 500
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
    // The ladder's edges: its signed five-bit windows run on min(k, n − k)
    // and take −Q for the other half, which keeps every addition away from
    // the doubling case. So the scalars around (n − 1)/2 and n, the digit
    // edges ±15 … ±17 and ±31 … ±33, powers of two, 0, n and n + 1.
    : ( Vec s ) edges ( vec_new [s] )
    ( vec_push [s] edges `0000000000000000000000000000000000000000000000000000000000000001` )
    ( vec_push [s] edges `0000000000000000000000000000000000000000000000000000000000000002` )
    ( vec_push [s] edges `000000000000000000000000000000000000000000000000000000000000000f` )
    ( vec_push [s] edges `0000000000000000000000000000000000000000000000000000000000000010` )
    ( vec_push [s] edges `0000000000000000000000000000000000000000000000000000000000000011` )
    ( vec_push [s] edges `000000000000000000000000000000000000000000000000000000000000001f` )
    ( vec_push [s] edges `0000000000000000000000000000000000000000000000000000000000000020` )
    ( vec_push [s] edges `0000000000000000000000000000000000000000000000000000000000000021` )
    ( vec_push [s] edges `7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a7` )
    ( vec_push [s] edges `7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8` )
    ( vec_push [s] edges `7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a9` )
    ( vec_push [s] edges `7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192aa` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc63254f` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632542` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632541` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632540` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632532` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632531` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632530` )
    ( vec_push [s] edges `8000000000000000000000000000000000000000000000000000000000000000` )
    ( vec_push [s] edges `7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` )
    ( vec_push [s] edges `0000000000000000000000000000000100000000000000000000000000000000` )
    ( vec_push [s] edges `00000000000000000000000000000000ffffffffffffffffffffffffffffffff` )
    ( vec_push [s] edges `0000000000000000000000000000000000000000000000000000000000000000` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551` )
    ( vec_push [s] edges `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632552` )
    : ~ i esame 0
    : ~ i ei 0
    ~ < ei 27 {
        : s hx ?? ( vec_get [s] edges ei ) { T x → x F _ → `00` }
        : ( Vec u ) k ?? ( bytes_from_hex hx ) { T v → v F _ → ( vec_new [u] ) }
        ? ( bytes_eq ( p256ct_scalarmult_base k ) ( p256ct_scalarmult k gx gy ) ) { = esame + esame 1 } {
            ( nurl_print `EDGE MISMATCH ` ) ( nurl_print hx ) ( nurl_print `\n` )
        }
        = ei + ei 1
    }
    ( nurl_print `edges: ` ) ( nurl_print_int esame ) ( nurl_print `/27\n` )
    ^ ? & == same 500 == esame 27 0 1
}
