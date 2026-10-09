// H132: the H131 option handed back: the caller took it for a view, and the string leaked there.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ f s a → ?s { ^ @ ?s { T ( nurl_str_cat a `bc` ) } }

@ main → i {
    : ?s o ( f `x` )
    ?? o { T v → { ( nurl_print v ) } F → {} }
    ( nurl_print `\n` )
    ^ 0
}
