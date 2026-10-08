// H102: a null string (`# s 0`, an unset getenv) printed or measured crashed in C.
$ `stdlib/core/string.nu`

@ main → i {
    : s z # s 0
    ( nurl_println z )
    ( nurl_println_int ( nurl_str_len z ) )
    ( nurl_println_int ( strlen ( getenv `NURL_SURELY_UNSET_VARIABLE_XYZ` ) ) )
    : String t ( string_from z )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
