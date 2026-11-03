// mem_dup_of_a_view_pushed_out: mem_dup of a view of a block-local String, pushed into an outer Vec.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #368: mem_dup of a view of a block-local String, pushed into an outer Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec s ) out ( vec_new [s] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : s sv ( string_data line )
        ( vec_push [s] out ( mem_dup sv ) )
    }
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
