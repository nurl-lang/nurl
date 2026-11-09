// loop_over_a_copy_of_a_row_read_after_the_original_is_cleared_runs_clean: agora #482 — `~ x b` over `b`, a copy of `vv`'s row (`mem_dup`); `vv` cleared in the body; `x` read after
// The shape the fix must keep: a copy owns its elements (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop over a copy of a row read after the original is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) b ( mem_dup ( vec_at [( Vec String )] vv 0 ) )
    ~ x b {
        ( vec_clear [( Vec String )] vv )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
