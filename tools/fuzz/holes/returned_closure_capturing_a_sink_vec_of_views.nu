// returned_closure_capturing_a_sink_vec_of_views: a returned closure that took over a sink Vec of views.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.5 | A2 | rejected | - | agora #362: a returned closure that took over a sink Vec of views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk sink ( Vec s ) v → ( @ v ) { ^ \ → v { ( nurl_println ( vec_at [s] v 0 ) ) } }

@ main → i {
    : ~ ( @ v ) c \ → v {}
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = c ( mk t )
    }
    ( c )
    ^ 0
}
