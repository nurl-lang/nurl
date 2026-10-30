// field_reassign_old_alias: handle aliased out of a field, field reassigned (old dropped), alias read.
// map: §2.10 | A2 | rejected | h25 | view of a struct's String field read after the field is reassigned
$ `stdlib/core/string.nu`

: Holder { String v }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `first heap string value, long enough` ) }
    : s view ( string_data . h v )
    = . h v ( string_from `second` )
    ( nurl_println view )
    ^ 0
}
