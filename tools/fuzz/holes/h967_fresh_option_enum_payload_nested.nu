// H967: agora #208 — the same with `?? e { EV r → … }` inside the arm (fresh_option_enum_payload_nested).
// Closed: A fresh call's option or result whose payload cannot be copied and has a compiler-made drop (an enum holding a `% Drop` value) registers that payload as owned by the call's bit, as a String / Vec payload is (gen_match, agora #208).
// main: accepted; LeakSanitizer reported a leak.
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
    ?? ( mke ) { T e → { ?? e { EV r → ( nurl_println_int ( vec_len [i] . r buf ) ) EN n → {} } } F → {} }
    ^ 0
}
