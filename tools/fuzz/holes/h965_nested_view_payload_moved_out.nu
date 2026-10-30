// H965: agora #208 — the inner payload of a `vec_get` element pushed into another Vec: both Vecs dropped it (nested_view_payload_moved_out).
// Closed: A `??` over a name that owns nothing itself — not a parameter, no owner slot: an arm's payload, a view — lends a payload that cannot be copied to its arms (flag 0, `__sborrow`), for an enum and for an option alike (gen_match, agora #208).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mkres → Res {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ^ @ Res { v }
}

: | E { EV Res EN i }

@ main → i {
    : ( Vec E ) xs ( vec_new [E] )
    ( vec_push [E] xs @ E { EV ( mkres ) } )
    : ~ ( Vec Res ) ys ( vec_new [Res] )
    ?? ( vec_get [E] xs 0 ) { T e → { ?? e { EV r → ( vec_push [Res] ys r ) EN n → {} } } F → {} }
    ( nurl_println_int + ( vec_len [E] xs ) ( vec_len [Res] ys ) )
    ^ 0
}
