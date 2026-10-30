// field_read_into_owned_string: a string binding that owns its value, assigned a struct's string field, stored the field's own pointer: the binding freed it (an invalid free of a literal field; a double free of an owned one).
// map: §2.13 | A2 | runs-clean | h121 | owning s binding assigned struct field pointer; frees field (bad free)
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ main → i {
    : Rec r @ Rec { `abc` 1 }
    : ~ s p ``
    = p . r name
    ( nurl_print_int ( nurl_str_len p ) ) ( nurl_print `\n` )
    ^ 0
}
