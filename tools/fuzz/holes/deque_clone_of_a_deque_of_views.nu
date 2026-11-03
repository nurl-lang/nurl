// deque_clone_of_a_deque_of_views: Deque_clone of a Deque of structs of views outlives the strings.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #377: Deque_clone of a Deque of structs of views outlives the strings
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/deque.nu`

: W { s v }

@ main → i {
    : ~ ( Deque W ) keep ( deque_new [W] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Deque W ) d ( deque_new [W] )
        ( deque_push_back [W] d @ W { ( string_data b ) } )
        = keep ( Deque_clone [W] d )
    }
    ?? ( deque_pop_front [W] keep ) { T w → ( nurl_println . w v ) F → {} }
    ^ 0
}
