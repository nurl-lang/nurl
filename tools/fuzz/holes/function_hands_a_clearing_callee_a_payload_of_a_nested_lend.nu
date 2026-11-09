// function_hands_a_clearing_callee_a_payload_of_a_nested_lend: agora #461 — `top` matches the payload of `( vec_get ( vec_at vvv 0 ) 0 )` and hands it to `clr`
// Closed: a `??` payload of a call whose lend no name carries is read out of the parameters its source expression names, under that condition (agora #461).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function hands a clearing callee a payload of a nested lend
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec ( Vec String ) ) ) vvv → v {
    ?? ( vec_get [( Vec String )] ( vec_at [( Vec ( Vec String ) )] vvv 0 ) 0 ) { T e → { ( clr e ) } F → {} }
}

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) w ( vec_new [( Vec ( Vec String ) )] )
    ( vec_push [( Vec ( Vec String ) )] w ( vec_new [( Vec String )] ) )
    : ( Vec ( Vec String ) ) m ( vec_at [( Vec ( Vec String ) )] w 0 )
    ( vec_push [( Vec String )] m ( vec_new [String] ) )
    : ( Vec String ) r ( vec_at [( Vec String )] m 0 )
    ( vec_push [String] r ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( top w )
    ( nurl_println d )
    ^ 0
}
