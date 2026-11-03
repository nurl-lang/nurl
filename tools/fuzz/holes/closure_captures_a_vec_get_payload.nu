// closure_captures_a_vec_get_payload: agora #463 — `?? ( vec_get [?String] v 0 ) { T e → { ^ \ → i { ?? e { … } } } … }`
// Closed: a payload of a `vec_get` result captured by a closure is a capture in its body, not a slot of the enclosing function's Vec (it failed to build) (agora #463).
// main: failed to build (use of an undefined value in the IR) (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `?? ( vec_get [?String] v 0 ) { T e → { ^ \ → i { ?? e { … } } } … }`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cap ( Vec ? String ) v → ( @ i ) {
    ?? ( vec_get [? String] v 0 ) { T e → { ^ \ → i { ?? e { T s → { ^ ( string_len s ) } F → { ^ 0 } } } } F → {} }
    ^ \ → i { ^ 0 }
}

@ main → i {
    : ( Vec ? String ) v ( vec_new [? String] )
    ( vec_push [? String] v @ ?String { T ( string_from `an element value long enough for the heap` ) } )
    : ( @ i ) c ( cap v )
    ( nurl_println_int ( c ) )
    ^ 0
}
