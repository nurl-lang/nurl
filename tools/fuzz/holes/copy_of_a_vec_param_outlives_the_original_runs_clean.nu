// copy_of_a_vec_param_outlives_the_original_runs_clean: a copy of a ( Vec s ) parameter outlives the original; the strings outlive both.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 836c0e9: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #377: a copy of a ( Vec s ) parameter outlives the original; the strings outlive both
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cp ( Vec s ) v → ( Vec s ) { ^ ( vec_clone [s] v ) }

@ main → i {
    : String b ( string_from `a string that outlives ws` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( cp t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
