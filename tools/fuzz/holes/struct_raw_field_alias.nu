// struct_raw_field_alias: a struct owning a raw string field, copied to an outer binding; the field is freed with the inner one.
// map: §2.13 | A2 | rejected | h30 | struct with owned raw-string field copied out of block; field freed
$ `stdlib/core/string.nu`

: Resp { s body i code }

@ main → i {
    : ~ Resp out @ Resp { `none` 500 }
    ? > ( nurl_str_len `ab` ) 1 {
        : Resp tmp @ Resp { ( nurl_str_cat `escaped-` `field` ) 201 }
        = out tmp
    } {}
    ( nurl_print . out body ) ( nurl_print `\n` )
    ^ 0
}
