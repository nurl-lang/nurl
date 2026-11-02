// closure_returns_a_value_viewing_a_live_capture_runs_clean: the same with the captured String alive throughout.
// Must keep compiling and running clean beside agora #369's rule.
// main's compiler: compiled, ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #369: the same with the captured String alive throughout
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ main → i {
    : ~ ( Vec Tok ) toks ( vec_new [Tok] )
    : String line ( string_from `the outer string, alive throughout` )
    : ( @ Tok ) mk \ → Tok { ^ @ Tok { Word ( string_data line ) } }
    ( vec_push [Tok] toks ( mk ) )
    ?? ( vec_at [Tok] toks 0 ) { Word w → { ( nurl_println w ) } Num n → {} Bad m → {} }
    ( vec_free [Tok] toks )
    ^ 0
}
