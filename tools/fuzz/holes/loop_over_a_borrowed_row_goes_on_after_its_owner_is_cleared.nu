// loop_over_a_borrowed_row_goes_on_after_its_owner_is_cleared: agora #482 — `~ x b` over `b = ( vec_at vv 0 )` (two elements); `x` read, then `vv` cleared: the next round reads the freed row
// Closed: a loop whose element ended with its storage, on a path that goes on to its next element, is refused (bck_diag_fe_next, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a borrowed row goes on after its owner is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) b ( vec_at [( Vec String )] vv 0 )
    ~ x b {
        ( nurl_println ( string_data x ) )
        ( vec_clear [( Vec String )] vv )
    }
    ^ 0
}
