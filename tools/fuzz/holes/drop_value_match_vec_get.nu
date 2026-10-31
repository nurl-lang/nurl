// drop_value_match_vec_get: agora #203 — a value-position `?? ( vec_get [Res] xs 0 )`: the arm dropped the element (drop_value_match_vec_get).
// Closed: A `??` over a call that lends what it hands back — a value borrow (`vec_get`) or a view of an argument the callee does not answer per call for (`__m_call_lent`) — lends a `% Drop` payload to its arms (flag 0); a `vec_get` element stays one a consumer may take (agora #203).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h947 | a value-position `??` over `vec_get`
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
    : i n ?? ( vec_get [Res] xs 0 ) { T e → ( vec_len [i] . e buf ) F → 0 }
    ( nurl_println_int n )
    ( nurl_println_int ( vec_len [Res] xs ) )
    ^ 0
}
