// loop_over_a_borrowed_row_read_after_a_helper_grows_its_owner_runs_clean: agora #482 — `~ x b` over `b = ( vec_at vv 0 )`; a helper grows `vv` in the body; `x` read after
// The shape the fix must keep: growing the owner moves no row (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop over a borrowed row read after a helper grows its owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec ( Vec String ) ) v → v {
    : ~ i k 0
    ~ < k 32 {
        ( vec_push [( Vec String )] v ( vec_new [String] ) )
        = k + k 1
    }
}

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) b ( vec_at [( Vec String )] vv 0 )
    ~ x b {
        ( grow vv )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
