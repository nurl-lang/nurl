// string_with_cap_overflow: string_with_cap with a capacity whose size wraps.
// map: §6.2 | B | runs-clean | h78 | string_with_cap capacity size wraps
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_with_cap 9223372036854775807 )
    ( string_push_str t `abcdefghijklmnopqrstuvwxyz` )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
