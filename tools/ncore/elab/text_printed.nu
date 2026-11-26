// Text printed: a literal, an owned String, a view of it, raw text.
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abc` )
    ( nurl_println `hello` )
    ( nurl_println ( string_data t ) )
    : s v ( string_data t )
    ( nurl_println v )
    : s u ( nurl_str_cat `x` `y` )
    ( nurl_println u )
    ^ 0
}
