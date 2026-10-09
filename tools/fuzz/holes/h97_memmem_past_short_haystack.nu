// H97: memmem told a haystack longer than the string it is handed reads past the string's block.
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `hay` )
    : s r ( memmem ( string_data a ) 4096 `zz` 2 )
    ( nurl_println_int ? == 0 # i r 0 1 )
    ^ 0
}
