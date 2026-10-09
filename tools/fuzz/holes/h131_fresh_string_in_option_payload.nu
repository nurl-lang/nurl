// H131: a fresh string as an option payload: an option of a raw string owns nothing, so the string leaked.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ main → i {
    : ?s o @ ?s { T ( nurl_str_cat `a` `bc` ) }
    ?? o { T v → { ( nurl_print v ) } F → {} }
    ( nurl_print `\n` )
    ^ 0
}
