// filter_closure_capturing_a_short_lived_view_runs_clean: a vec_filter closure captures a view that outlives only the call.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 4f15689: accepted; ran clean.
// map: §7.5 | A2 | runs-clean | - | agora #377: a vec_filter closure captures a view that outlives only the call
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String b ( string_from `a string that outlives ws` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ( Vec s ) t ( vec_new [s] )
    ( vec_push [s] t ( string_data b ) )
    {
        : String nd ( string_from `a needle freed at the end of its block` )
        : s needle ( string_data nd )
        = ws ( vec_filter [s] t \ s x → b { ^ != 0 ( nurl_str_len needle ) } )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
