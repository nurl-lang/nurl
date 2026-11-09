// loop_over_a_borrowed_row_read_after_its_owner_gets_a_new_value: agora #482 — `~ x b` over `b = ( vec_at vv 0 )`; `vv` given a new value in the body; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a borrowed row, its owner given a new value in the body
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) b ( vec_at [( Vec String )] vv 0 )
    ~ x b {
        = vv ( vec_new [( Vec String )] )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
