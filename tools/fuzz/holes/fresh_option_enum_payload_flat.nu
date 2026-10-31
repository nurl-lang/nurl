// fresh_option_enum_payload_flat: agora #208 — `?? ( mke ) { T e → … }`, mke handing over a fresh `?E`: e, owned by nothing, leaked (fresh_option_enum_payload_flat).
// Closed: A fresh call's option or result whose payload cannot be copied and has a compiler-made drop (an enum holding a `% Drop` value) registers that payload as owned by the call's bit, as a String / Vec payload is (gen_match, agora #208).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h966 | a fresh `?E` whose enum holds a `% Drop` value: its payload was owned by nothing and leaked
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
    ?? ( mke ) { T e → ( nurl_println_int 1 ) F → {} }
    ^ 0
}
