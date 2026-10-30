// vget_payload_in_local_struct: agora #204 — `T e → { : Hold h @ Hold { e 1 } … }`, xs a local: h and xs both dropped the element (vget_payload_in_local_struct).
// Closed: A `vec_get` element moved into a literal (a bare identifier with `__vget` whose type needs drop) is taken out of its Vec slot, as a consumer argument takes it (mem_vget_consume, gen_agg_lit; agora #204).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h959 | a `vec_get` payload moved into a local struct: the struct and the Vec both dropped it
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

@ main → i {
    : ( Vec Res ) xs ( vec_new [Res] )
    ( vec_push [Res] xs ( mkres ) )
    : ~ i k 0
    ?? ( vec_get [Res] xs 0 ) { T e → { : Hold h @ Hold { e 1 } = k ( vec_len [i] . . h r buf ) } F → {} }
    ( nurl_println_int k )
    ( nurl_println_int ( vec_len [Res] xs ) )
    ^ 0
}
