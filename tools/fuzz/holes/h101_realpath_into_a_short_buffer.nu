// H101: realpath writes a whole path into a caller's buffer of any size.
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `x` )
    : s r ( realpath `/usr/lib/../usr/lib/../usr/lib/../usr/lib/../usr/lib/../usr/lib` ( string_data a ) )
    ( nurl_println_int ? == # i r 0 0 1 )
    ^ 0
}
