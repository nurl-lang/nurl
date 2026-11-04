// slice_param_copy_outlives_its_vec_runs_clean: slice_to_vec of a Slice parameter outlives the Vec it viewed.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 836c0e9: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #377: slice_to_vec of a Slice parameter outlives the Vec it viewed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ cps ( Slice s ) p → ( Vec s ) { ^ ( slice_to_vec [s] p ) }

@ main → i {
    : String b ( string_from `a string that outlives ws` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( cps ( slice_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
