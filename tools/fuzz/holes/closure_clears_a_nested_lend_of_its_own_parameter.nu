// closure_clears_a_nested_lend_of_its_own_parameter: agora #461 — a closure clears `( vec_at ( vec_at p 0 ) 0 )` of its own parameter; a runner calls it with `w`
// Closed: a closure body's argument named by its source expression adds its drop edges to the closure's summary as names do (agora #461).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #461: a closure clears a nested lend of its own parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ run ( @ v ( Vec ( Vec ( Vec String ) ) ) ) f ( Vec ( Vec ( Vec String ) ) ) x → v {
    ( f x )
}

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) w ( vec_new [( Vec ( Vec String ) )] )
    ( vec_push [( Vec ( Vec String ) )] w ( vec_new [( Vec String )] ) )
    ( vec_push [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) 0 ) )
    ( run \ ( Vec ( Vec ( Vec String ) ) ) p → v { ( clr ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] p 0 ) 0 ) ) } w )
    ( nurl_println d )
    ^ 0
}
