// generic_instance_compiled_after_the_lender_it_calls_hands_on_an_element: agora #461 — a generic `each0` whose instance is compiled after main's `vec_at` instance it calls
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a generic instance compiled after the lender it calls hands on an element
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clrv [T] ( Vec T ) v → v {
    ( vec_clear [T] v )
}

@ each0 [T] ( Vec ( Vec T ) ) vv → v {
    ( clrv [T] ( vec_at [( Vec T )] vv 0 ) )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    : ( Vec String ) r ( vec_at [( Vec String )] w 0 )
    ( vec_push [String] r ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( run w )
    ( nurl_println d )
    ^ 0
}

@ run ( Vec ( Vec String ) ) w → v {
    ( each0 [String] w )
}
