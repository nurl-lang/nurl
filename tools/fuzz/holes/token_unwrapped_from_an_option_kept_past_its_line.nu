// token_unwrapped_from_an_option_kept_past_its_line: opt_unwrap_or of an option of a token outlives its line.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #368: opt_unwrap_or of an option of a token outlives its line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ~ Tok keep @ Tok { Num 0 }
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ?Tok o @ ?Tok { T @ Tok { Word ( string_data line ) } }
        = keep ( opt_unwrap_or [Tok] o @ Tok { Num 1 } )
    }
    ( show keep )
    ^ 0
}
