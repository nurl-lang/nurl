// mem_dup_of_a_token_kept_past_its_line: mem_dup of a token given to an outer binding outlives its line.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #368: mem_dup of a token given to an outer binding outlives its line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ main → i {
    : ~ Tok keep @ Tok { Num 1 }
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : Tok t @ Tok { Word ( string_data line ) }
        = keep ( mem_dup t )
    }
    ?? keep { Word w → ( nurl_println w ) Num n → {} Bad b → {} }
    ^ 0
}
