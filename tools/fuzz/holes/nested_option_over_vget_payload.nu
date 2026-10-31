// nested_option_over_vget_payload: agora #208 — the same over a `( Vec ?Res )` element (nested_option_over_vget_payload).
// Closed: A `??` over a name that owns nothing itself — not a parameter, no owner slot: an arm's payload, a view — lends a payload that cannot be copied to its arms (flag 0, `__sborrow`), for an enum and for an option alike (gen_match, agora #208).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h963 | the same over an option element
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
    : ( Vec ? Res ) xs ( vec_new [? Res] )
    ( vec_push [? Res] xs @ ?Res { T ( mkres ) } )
    ?? ( vec_get [? Res] xs 0 ) { T o → { ?? o { T r → ( nurl_println_int ( vec_len [i] . r buf ) ) F → {} } } F → {} }
    ?? ( vec_get [? Res] xs 0 ) { T o → { ?? o { T r → ( nurl_println_int ( vec_len [i] . r buf ) ) F → {} } } F → {} }
    ^ 0
}
