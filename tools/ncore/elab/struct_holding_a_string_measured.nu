// A struct holding a String: the String moved in, its field read and measured.
$ `stdlib/core/string.nu`

: N { String name i n }

@ main → i {
    : String s ( string_from `abc` )
    : N x @ N { s 1 }
    : s v ( string_data . x name )
    ( nurl_println v )
    ^ + ( string_len . x name ) . x n
}
