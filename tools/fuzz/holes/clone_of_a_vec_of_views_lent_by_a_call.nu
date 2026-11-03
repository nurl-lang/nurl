// clone_of_a_vec_of_views_lent_by_a_call: vec_clone of the Vec a call lends, holding views of a block-local String.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #377: vec_clone of the Vec a call lends, holding views of a block-local String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mkv String b → ( Vec s ) { : ( Vec s ) v ( vec_new [s] ) ( vec_push [s] v ( string_data b ) ) ^ v }

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        = ws ( vec_clone [s] ( mkv b ) )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
