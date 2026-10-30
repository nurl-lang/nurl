// H960: agora #204 — the same with xs a parameter: h dropped the caller's element (vget_payload_in_struct_param_vec).
// Closed: A `vec_get` element moved into a literal (a bare identifier with `__vget` whose type needs drop) is taken out of its Vec slot, as a consumer argument takes it (mem_vget_consume, gen_agg_lit; agora #204).
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

: Hold { Res r i n }

@ use ( Vec Res ) xs → i {
    : ~ i k 0
    ?? ( vec_get [Res] xs 0 ) { T e → { : Hold h @ Hold { e 1 } = k ( vec_len [i] . . h r buf ) } F → {} }
    ^ k
}

@ main → i {
    : ( Vec Res ) xs ( vec_new [Res] )
    ( vec_push [Res] xs ( mkres ) )
    ( nurl_println_int ( use xs ) )
    ( nurl_println_int ( vec_len [Res] xs ) )
    ?? ( vec_get [Res] xs 0 ) { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → {} }
    ^ 0
}
