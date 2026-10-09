// H139: a struct binding reassigned a literal with a fresh raw string field it had not registered: the reassignment kept the old registration, and the fresh string leaked.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ main → i {
    : ~ Rec r @ Rec { `x` 0 }
    = r @ Rec { ( nurl_str_cat `a` `bc` ) 1 }
    ( nurl_print . r name ) ( nurl_print `\n` )
    ^ 0
}
