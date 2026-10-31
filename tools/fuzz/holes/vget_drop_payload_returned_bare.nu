// vget_drop_payload_returned_bare: agora #209 — a `% Drop` element handed back bare out of a local Vec (vget_drop_payload_returned_bare).
// Closed: a `??` payload whose call lends out of a local of this frame (`mem_payload_local_lend`: the payload's `__pljk` / `__pljr`) is taken out of its `vec_get` slot, or copied where it lent, when it is handed back bare or as a returned literal's field; the function answers per call (agora #209).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | a `% Drop` element of a local Vec handed back bare
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

@ first i n → Res {
    : ( Vec Res ) xs ( vec_new [Res] )
    ( vec_push [Res] xs ( mkres ) )
    ?? ( vec_get [Res] xs 0 ) { T e → { ^ e } F → {} }
    ^ ( mkres )
}

@ main → i {
    : Res r ( first 1 )
    ( nurl_println_int ( vec_len [i] . r buf ) )
    ^ 0
}
