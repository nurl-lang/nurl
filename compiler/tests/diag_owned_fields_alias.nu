// diag_owned_fields_alias.nu — a struct whose raw string field it owns,
// copied to a binding that outlives it. `tmp`'s field is freed when
// `tmp`'s block ends; `out` would still point at it (this program read
// freed memory before the rule). The fix: an owning field type (String)
// so the value moves, or build the struct where it is kept.
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
