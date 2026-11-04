// view_of_a_loop_element_over_a_field_of_a_vec_at_call_kept_while_another_param_is_cleared_runs_clean: agora #471 — `@ first ( Vec String ) other ( Vec B ) bs → s` hands back a view of a loop element over `. ( vec_at [B] bs 0 ) items`; the caller clears `other`, an unrelated first argument, then reads the view (the shape the fix must keep)
// Closed: a container path rooted at a call is a part of what the call lends: the loop element's `fe_` names the bindings the call lends (bck_sx_hroots), not an id its text read as (agora #471).
// main 9d2e7cd: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: a bare view of a loop element over a field of a vec_at call, kept while an unrelated argument is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec String ) items i n }

@ first ( Vec String ) other ( Vec B ) bs → s {
    ~ x . ( vec_at [B] bs 0 ) items { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : ( Vec String ) other ( vec_new [String] )
    ( vec_push [String] other ( string_from `an unrelated string` ) )
    : ( Vec B ) bs ( vec_new [B] )
    ( vec_push [B] bs @ B { ( vec_new [String] ) 0 } )
    ( vec_push [String] . ( vec_at [B] bs 0 ) items ( string_from `a string that lives as long as bs` ) )
    : s v ( first other bs )
    ( vec_clear [String] other )
    ( nurl_println v )
    ^ 0
}
