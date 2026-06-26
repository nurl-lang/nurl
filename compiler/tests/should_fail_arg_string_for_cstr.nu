// The converse: passing a `String` where a raw C-string `s` (i8*) is
// declared must also be rejected. Convert with `string_data`.
$ `stdlib/core/string.nu`

@ takes_cstr s p → i { ^ ( nurl_str_len p ) }

@ main → i {
    : String x ( string_from `hello` )
    ^ ( takes_cstr x )
}
