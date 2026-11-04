// view_of_a_nested_loop_element_kept_while_the_outer_container_grows_runs_clean: agora #471 — views of `~ v vv { ~ x v { … } }` elements read after `vv` grew (the shape the fix must keep)
// Closed: the outer container growing moves its rows' handles, not the Strings' buffers: the views, reached through its elements (`^vv`), stay (agora #471).
// main 0c11a93: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: views of nested loop elements read after the outer container grew
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec s ) ws ( vec_new [s] )
    ~ v vv { ~ x v { ( vec_push [s] ws ( string_data x ) ) } }
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
