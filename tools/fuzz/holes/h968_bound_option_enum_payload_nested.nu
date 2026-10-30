// H968: agora #208 — `: ?E o ( mke )  ?? o { T e → { ?? e { EV r → … } } }`: the inner arm dropped r, and o dropped it again (bound_option_enum_payload_nested).
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

@ mke → ?E { ^ @ ?E { T @ E { EV ( mkres ) } } }

@ main → i {
    : ?E o ( mke )
    ?? o { T e → { ?? e { EV r → ( nurl_println_int ( vec_len [i] . r buf ) ) EN n → {} } } F → {} }
    ^ 0
}
