// fresh_string_in_option_payload: a fresh string as an option payload: an option of a raw string owns nothing, so the string leaked.
// map: §2.13 | A2 | rejected | h131 | fresh string as ?s option payload leaks
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ main → i {
    : ?s o @ ?s { T ( nurl_str_cat `a` `bc` ) }
    ?? o { T v → { ( nurl_print v ) } F → {} }
    ( nurl_print `\n` )
    ^ 0
}
