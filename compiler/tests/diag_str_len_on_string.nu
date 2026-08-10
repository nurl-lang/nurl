// diag_str_len_on_string.nu — 'nurl_str_len' handed a %String. The two
// length functions are not interchangeable and the names give no hint
// which is which, so the message has to name the other one.
$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_from `hi` )
    : i n ( nurl_str_len s )
    ( string_free s )
    ^ n
}
