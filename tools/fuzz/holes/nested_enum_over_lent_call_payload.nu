// nested_enum_over_lent_call_payload: agora #208 — `?? ( get_e h ) { T e → { ?? e { EV r → … } } }`, get_e = `^ @ ?E { T . h e }`: the inner arm dropped h's Res (nested_enum_over_lent_call_payload).
// Closed: A `??` over a name that owns nothing itself — not a parameter, no owner slot: an arm's payload, a view — lends a payload that cannot be copied to its arms (flag 0, `__sborrow`), for an enum and for an option alike (gen_match, agora #208).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h964 | the same over the option payload of a call lending a parameter's field
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
: H { E e i n }

@ get_e H h → ?E { ^ @ ?E { T . h e } }

@ main → i {
    : H h @ H { @ E { EV ( mkres ) } 1 }
    ?? ( get_e h ) { T e → { ?? e { EV r → ( nurl_println_int ( vec_len [i] . r buf ) ) EN n → ( nurl_println_int n ) } } F → {} }
    ?? . h e { EV r → ( nurl_println_int ( vec_len [i] . r buf ) ) EN n → ( nurl_println_int n ) }
    ^ 0
}
