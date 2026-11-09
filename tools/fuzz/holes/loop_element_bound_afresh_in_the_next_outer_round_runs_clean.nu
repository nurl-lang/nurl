// loop_element_bound_afresh_in_the_next_outer_round_runs_clean: agora #482 — inside an outer loop, `~ x a {}`, then the owner of `a` cleared, then `~ x b {}` again: the next round binds `x` afresh
// The shape the fix must keep: each round binds the element afresh (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop element bound afresh in the next outer round
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ i k 0
    ~ < k 2 {
        : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
        : ~ ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
        ( vec_push [( Vec String )] vv t )
        : ( Vec String ) a ( vec_at [( Vec String )] vv 0 )
        : ( Vec String ) b ( vec_new [String] )
        ( vec_push [String] b ( string_from `another string long enough for a heap buffer` ) )
        ~ x a { ( nurl_println ( string_data x ) ) }
        ( vec_clear [( Vec String )] vv )
        ~ x b { ( nurl_println ( string_data x ) ) }
        = k + k 1
    }
    ^ 0
}
