// H944: agora #203 — `?? ( pass2 r )` through two passes: the arm dropped r's payload (drop_nested_alias_scrut_arm).
// Closed: A `??` over a call that lends what it hands back — a value borrow (`vec_get`) or a view of an argument the callee does not answer per call for (`__m_call_lent`) — lends a `% Drop` payload to its arms (flag 0); a `vec_get` element stays one a consumer may take (agora #203).
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

@ pass ? Res q → ?Res { ^ q }

@ pass2 ? Res q → ?Res { ^ ( pass q ) }

@ main → i {
    : ?Res r @ ?Res { T ( mkres ) }
    ?? ( pass2 r ) { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ?? r { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ^ 0
}
