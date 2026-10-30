// H945: agora #203 — `?? ( pass r ) { … F e → … }` over an `!i Res`: the Err arm dropped r's error (drop_result_err_alias_scrut_arm).
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

@ pass ! i Res q → !i Res { ^ q }

@ main → i {
    : !i Res r @ !i Res { F ( mkres ) }
    ?? ( pass r ) { T x → ( nurl_println_int x ) F e → ( nurl_println_int ( vec_len [i] . e buf ) ) }
    ?? r { T x → ( nurl_println_int x ) F e → ( nurl_println_int ( vec_len [i] . e buf ) ) }
    ^ 0
}
