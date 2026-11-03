// wrapper_that_only_reads_its_vec_defined_below_runs_clean: the reading wrapper defined below its caller.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 4f15689: accepted; ran clean.
// map: §2.7 | A2 | runs-clean | - | agora #377: the reading wrapper defined below its caller
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( count_into ws t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}

@ count_into inout ( Vec s ) d ( Vec s ) t → v { ( vec_push [s] d `n` ) ( nurl_println_int ( vec_len [s] t ) ) }
