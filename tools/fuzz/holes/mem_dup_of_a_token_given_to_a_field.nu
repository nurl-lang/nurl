// mem_dup_of_a_token_given_to_a_field: mem_dup of a token given to a field of an outer holder outlives its line.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #368: mem_dup of a token given to a field of an outer holder outlives its line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tok { s w }
: H { ( Vec Tok ) items Tok last }

@ main → i {
    : ~ H h @ H { ( vec_new [Tok] ) @ Tok { `x` } }
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : Tok t @ Tok { ( string_data line ) }
        = . h last ( mem_dup t )
    }
    ( nurl_println . . h last w )
    ^ 0
}
