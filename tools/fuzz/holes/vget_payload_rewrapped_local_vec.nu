// vget_payload_rewrapped_local_vec: agora #204 — the same with xs a local: xs, dropped on the way out, freed the result's element (vget_payload_rewrapped_local_vec).
// Closed: A `vec_get` element moved into a literal (a bare identifier with `__vget` whose type needs drop) is taken out of its Vec slot, as a consumer argument takes it (mem_vget_consume, gen_agg_lit; agora #204).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h958 | the same out of a local Vec, dropped on the way out
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

@ first i n → ?Res {
    : ( Vec Res ) xs ( vec_new [Res] )
    ( vec_push [Res] xs ( mkres ) )
    ?? ( vec_get [Res] xs 0 ) { T e → { ^ @ ?Res { T e } } F → {} }
    ^ @ ?Res { F }
}

@ main → i {
    ?? ( first 1 ) { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ^ 0
}
