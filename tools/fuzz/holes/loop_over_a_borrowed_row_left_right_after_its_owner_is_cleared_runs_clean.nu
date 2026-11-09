// loop_over_a_borrowed_row_left_right_after_its_owner_is_cleared_runs_clean: agora #482 — `~ x b` over `b = ( vec_at vv 0 )`; `x` read, then `vv` cleared and the loop left at once
// The shape the fix must keep: a loop left by `break` right after the change reads nothing more (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop over a borrowed row left right after its owner is cleared
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
        break
    }
    ^ 0
}
