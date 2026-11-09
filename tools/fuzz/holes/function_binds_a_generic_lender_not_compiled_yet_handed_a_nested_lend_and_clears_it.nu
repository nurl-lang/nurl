// function_binds_a_generic_lender_not_compiled_yet_handed_a_nested_lend_and_clears_it: agora #461 — in `top`, `: r ( geither [String] ( vec_at p 0 ) q k )`, the generic's instance not compiled yet, then `( clr r )`
// Closed: a lender whose lent positions are not known yet reads the local out of its lending arguments too, decided at module end (g_call_lend_unk, agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function binds a generic lender not compiled yet, handed a nested lend, and clears it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ geither [T] ( Vec T ) a ( Vec T ) b i k → ( Vec T ) {
    ^ ? > k 0 a b
}

@ top ( Vec ( Vec String ) ) p ( Vec String ) q ( Vec String ) q2 i k → v {
    : ( Vec String ) r ( geither [String] ( vec_at [( Vec String )] p 0 ) q k )
    ( clr r )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] w 0 ) ( string_from `a string long enough to live on the heap for sure` ) )
    : ( Vec String ) q0 ( vec_new [String] )
    : ( Vec String ) q1 ( vec_new [String] )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] w 0 ) 0 ) )
    ( top w q0 q1 1 )
    ( nurl_println d )
    ^ 0
}
