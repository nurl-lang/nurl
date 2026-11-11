// diag_view_lit_not_a_param.nu — agora #635: the same view placed in a
// literal that is handed back (`^ @ W { x 1 }`, x a `~` loop's element of
// a local Vec): the literal would hold a value its Vec releases on the
// way out.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

: W { Bomb b i n }

@ f → W {
    : ~ ( Vec Bomb ) loc ( vec_new [Bomb] )
    ( vec_push [Bomb] loc ( bomb `l0` 0 ) )
    ~ x loc { ^ @ W { x 1 } }
    ^ @ W { ( bomb `none` 0 ) 2 }
}

@ main → i {
    : W r ( f )
    ( see `main` . r b )
    ^ 0
}
