// memmem_past_short_haystack: memmem told a haystack longer than the string it is handed reads past the string's block.
// map: §6.4 | B | rejected | h97 | memmem given haystack length longer than string; reads past block
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `hay` )
    : s r ( memmem ( string_data a ) 4096 `zz` 2 )
    ( nurl_println_int ? == 0 # i r 0 1 )
    ^ 0
}
