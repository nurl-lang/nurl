// diag_owned_fields_alias.nu — a struct given a fresh raw string field,
// copied to a binding that outlives it. `tmp`'s field was freed when
// `tmp`'s block ended while `out` still pointed at it (this program read
// freed memory before the rules). A raw string field is a view in safe
// code (docs/MEMORY.md §2.13), so the fresh string is rejected where it is
// stored. The fix: an owning field type (String), so the value moves.
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
