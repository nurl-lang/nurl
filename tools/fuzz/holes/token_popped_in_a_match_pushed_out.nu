// token_popped_in_a_match_pushed_out: the payload of `?? ( vec_pop … )` pushed into an outer Vec outlives the line.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #368: the payload of `?? ( vec_pop … )` pushed into an outer Vec outlives the line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ( Vec Tok ) outer ( vec_new [Tok] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ( Vec Tok ) toks ( vec_new [Tok] )
        ( vec_push [Tok] toks @ Tok { Word ( string_data line ) } )
        ?? ( vec_pop [Tok] toks ) { T t → ( vec_push [Tok] outer t ) F → {} }
    }
    ( show ( vec_at [Tok] outer 0 ) )
    ^ 0
}
