// fresh_string_in_option_of_struct: a struct with a fresh raw string field inside an option literal: the option binding registers no fields, so the string leaked.
// map: §2.13 | A2 | rejected | h133 | struct with fresh s field inside option literal leaks
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ main → i {
    : ?Rec o @ ?Rec { T @ Rec { ( nurl_str_cat `a` `bc` ) 1 } }
    ?? o { T r → { ( nurl_print_int ( nurl_str_len . r name ) ) } F → {} }
    ( nurl_print `\n` )
    ^ 0
}
