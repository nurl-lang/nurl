// mem_dup_while_its_line_lives_runs_clean: mem_dup of a token whose line outlives the copy.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 836c0e9: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | agora #368: mem_dup of a token whose line outlives the copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ( Vec Tok ) outer ( vec_new [Tok] )
    {
        : Tok t @ Tok { Word ( string_data line ) }
        ( vec_push [Tok] outer ( mem_dup t ) )
    }
    ( show ( vec_at [Tok] outer 0 ) )
    ^ 0
}
