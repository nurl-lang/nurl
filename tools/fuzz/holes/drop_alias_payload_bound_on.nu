// drop_alias_payload_bound_on: agora #203 — `T e → { : Res k e … }` over `?? ( pass r )`: k dropped r's payload (drop_alias_payload_bound_on).
// Closed: A `??` over a call that lends what it hands back — a value borrow (`vec_get`) or a view of an argument the callee does not answer per call for (`__m_call_lent`) — lends a `% Drop` payload to its arms (flag 0); a `vec_get` element stays one a consumer may take (agora #203).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h946 | the lent payload bound on inside the arm
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

@ pass ? Res q → ?Res { ^ q }

@ main → i {
    : ?Res r @ ?Res { T ( mkres ) }
    : ~ i n 0
    ?? ( pass r ) { T e → { : Res k e = n ( vec_len [i] . k buf ) } F → ( nurl_println `none` ) }
    ( nurl_println_int n )
    ?? r { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ^ 0
}
