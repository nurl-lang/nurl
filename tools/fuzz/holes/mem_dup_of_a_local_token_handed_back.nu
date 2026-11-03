// mem_dup_of_a_local_token_handed_back: mem_dup of a token viewing a local, handed back.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #368: mem_dup of a token viewing a local, handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tok { s w }

@ mk → Tok {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : Tok t @ Tok { ( string_data line ) }
    ^ ( mem_dup t )
}

@ main → i {
    : Tok k ( mk )
    ( nurl_println . k w )
    ^ 0
}
