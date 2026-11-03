// vec_clone_of_a_param_handed_back: a function handing back vec_clone of its ( Vec s ) parameter.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #377: a function handing back vec_clone of its ( Vec s ) parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cp ( Vec s ) v → ( Vec s ) { ^ ( vec_clone [s] v ) }

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( cp t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
