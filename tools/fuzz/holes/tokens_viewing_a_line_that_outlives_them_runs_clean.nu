// tokens_viewing_a_line_that_outlives_them_runs_clean: tokens viewing a String that outlives them.
// The shape the fix must keep: a Vec of tokens viewing a String that outlives the Vec.
// main 24e95a81: runs clean.
// map: §2.13 | A2 | runs-clean | - | agora #338: tokens viewing a String that outlives them
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ( Vec Tok ) toks ( vec_new [Tok] )
    ( vec_push [Tok] toks @ Tok { Word ( string_data line ) } )
    ( vec_push [Tok] toks @ Tok { Num 7 } )
    ( vec_push [Tok] toks @ Tok { Bad ( string_from `bad` ) } )
    ( show ( vec_at [Tok] toks 0 ) )
    ( show ( vec_at [Tok] toks 2 ) )
    ^ 0
}
