// nested_clone_outlives_its_source_runs_clean: a clone of a clone outlives the Vec it copied.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 4f15689: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | agora #377: a clone of a clone outlives the Vec it copied
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String b ( string_from `a string that outlives ws` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( vec_clone [s] ( vec_clone [s] t ) )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
