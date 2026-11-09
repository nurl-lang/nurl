// later_loop_of_the_same_name_unaffected_by_the_first_ones_owner_runs_clean: agora #482 — `~ x a {}` then `~ x b {…}`: a later loop of the same name; the first one's owner cleared in it, its `x` read
// The shape the fix must keep: a loop's element is gone with its loop; a later one of the name is another value (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a later loop of the same name is not ended by the first loop's owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) a ( vec_at [( Vec String )] vv 0 )
    : ( Vec String ) b ( vec_new [String] )
    ( vec_push [String] b ( string_from `another string long enough for a heap buffer` ) )
    ~ x a { ( nurl_println ( string_data x ) ) }
    ~ x b {
        ( vec_clear [( Vec String )] vv )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
