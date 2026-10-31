// realpath_into_a_short_buffer: realpath writes a whole path into a caller's buffer of any size.
// map: §3 | B | rejected | h101 | FFI realpath writes whole path into a short string buffer
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `x` )
    : s r ( realpath `/usr/lib/../usr/lib/../usr/lib/../usr/lib/../usr/lib/../usr/lib` ( string_data a ) )
    ( nurl_println_int ? == # i r 0 0 1 )
    ^ 0
}
