// vec_extend_wrapper_source_released_first_runs_clean: the Vec given to a vec_extend wrapper is released first; its strings outlive the holder.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 836c0e9: accepted; ran clean.
// map: §2.7 | A2 | runs-clean | - | agora #377: the Vec given to a vec_extend wrapper is released first; its strings outlive the holder
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ ext inout ( Vec s ) d ( Vec s ) t → v { ( vec_extend [s] d t ) }

@ main → i {
    : String b ( string_from `a string that outlives ws` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( ext ws t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
