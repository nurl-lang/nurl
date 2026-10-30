// H941: agora #203 — `?? ( vec_get [Res] xs 0 ) { T e → … }`: the arm dropped the element xs still held (drop_vec_get_scrut_arm).
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

@ main → i {
    : ( Vec Res ) xs ( vec_new [Res] )
    ( vec_push [Res] xs ( mkres ) )
    ?? ( vec_get [Res] xs 0 ) { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ?? ( vec_get [Res] xs 0 ) { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ^ 0
}
