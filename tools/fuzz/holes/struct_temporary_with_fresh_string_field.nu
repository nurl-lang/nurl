// struct_temporary_with_fresh_string_field: a struct literal with a fresh string in a raw string field, passed as a temporary argument: the struct was dropped after the call, its string with no one.
// map: §2.13 | A2 | rejected | h129 | struct temp with fresh s field passed to call; string leaks
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ g Rec r → i { ^ ( nurl_str_len . r name ) }

@ main → i {
    ( nurl_print_int ( g @ Rec { ( nurl_str_cat `a` `bc` ) 1 } ) ) ( nurl_print `\n` )
    ^ 0
}
