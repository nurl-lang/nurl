// A String's text viewed (`string_data`), the view copied and read.
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abcdef` )
    : s v ( string_data t )
    : s w v
    : String u ( string_from w )
    ^ + + ( nurl_str_len v ) ( nurl_str_len w ) ( string_len u )
}
