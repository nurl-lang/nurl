// mem_dup_of_a_token_viewing_a_line_pushed_out: mem_dup of a token viewing a block-local line, pushed into an outer Vec.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #368: mem_dup of a token viewing a block-local line, pushed into an outer Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ( Vec Tok ) outer ( vec_new [Tok] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : Tok t @ Tok { Word ( string_data line ) }
        ( vec_push [Tok] outer ( mem_dup t ) )
    }
    ( show ( vec_at [Tok] outer 0 ) )
    ^ 0
}
