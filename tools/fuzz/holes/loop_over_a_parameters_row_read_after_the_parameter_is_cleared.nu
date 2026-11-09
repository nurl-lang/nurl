// loop_over_a_parameters_row_read_after_the_parameter_is_cleared: agora #482 — in a function, `~ x b` over `b = ( vec_at vv 0 )` with `vv` a parameter; `vv` cleared in the body; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a parameter's row, the parameter cleared in the body
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ walk ( Vec ( Vec String ) ) vv → v {
    : ( Vec String ) b ( vec_at [( Vec String )] vv 0 )
    ~ x b {
        ( vec_clear [( Vec String )] vv )
        ( nurl_println ( string_data x ) )
    }
}

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    ( walk vv )
    ^ 0
}
