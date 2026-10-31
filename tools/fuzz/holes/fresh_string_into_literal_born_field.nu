// fresh_string_into_literal_born_field: a fresh string assigned to a raw string field the struct was built with a literal in: the struct owns that field no more than the literal, so each one assigned leaked.
// map: §2.13 | A2 | rejected | h134 | fresh strings assigned to literal-born s field leak
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ main → i {
    : ~ Rec r @ Rec { `lit` 1 }
    = . r name ( nurl_str_cat `c` `de` )
    = . r name ( nurl_str_cat `f` `ghi` )
    ( nurl_print . r name ) ( nurl_print `\n` )
    ^ 0
}
