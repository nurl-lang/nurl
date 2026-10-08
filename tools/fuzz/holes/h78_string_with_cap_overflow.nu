// H78: string_with_cap with a capacity whose size wraps.
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_with_cap 9223372036854775807 )
    ( string_push_str t `abcdefghijklmnopqrstuvwxyz` )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
