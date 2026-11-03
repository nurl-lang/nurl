// clone_of_a_vec_of_strings_runs_clean: a copy of a ( Vec String ) holds no views.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 836c0e9: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #377: a copy of a ( Vec String ) holds no views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cp ( Vec String ) v → ( Vec String ) { ^ ( vec_clone [String] v ) }

@ main → i {
    : ~ ( Vec String ) ws ( vec_new [String] )
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `owned` ) )
        = ws ( cp t )
    }
    ( nurl_println ( string_data ( vec_at [String] ws 0 ) ) )
    ^ 0
}
