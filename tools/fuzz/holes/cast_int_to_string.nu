// cast_int_to_string: a String forged from an integer by a cast.
// map: §6.2 | B | rejected | h58 | String forged from an integer by a cast
$ `stdlib/core/string.nu`

@ main → i {
    : String t # String 4096
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
