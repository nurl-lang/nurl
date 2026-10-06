// H25: handle aliased out of a field, field reassigned (old dropped), alias read.
$ `stdlib/core/string.nu`

: Holder { String v }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `first heap string value, long enough` ) }
    : s view ( string_data . h v )
    = . h v ( string_from `second` )
    ( nurl_println view )
    ^ 0
}
