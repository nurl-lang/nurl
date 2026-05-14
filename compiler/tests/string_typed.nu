// Test: owned String from stdlib/core/string.nu
$ `stdlib/core/string.nu`

@ main → i {
    // Build a greeting by pushing pieces
    : String s ( string_new )
    ( string_push_str s `Hello` )
    ( string_push_char s 44 )  // ','
    ( string_push_char s 32 )  // ' '
    ( string_push_str s `world` )
    ( string_push_char s 33 )  // '!'
    ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
    ( nurl_print `len=` )
    ( nurl_print ( nurl_str_int ( string_len s ) ) ) ( nurl_print `\n` )

    // Append integer
    : String n ( string_new )
    ( string_push_str n `pi=` )
    ( string_push_int n 314 )
    ( nurl_print ( string_data n ) ) ( nurl_print `\n` )

    // Content equality
    : String a ( string_from `abc` )
    : String b ( string_from `abc` )
    : String c ( string_from `abd` )
    ( nurl_print ? ( string_eq a b ) `eq\n` `ne\n` )
    ( nurl_print ? ( string_eq a c ) `eq\n` `ne\n` )

    // Byte access
    ( nurl_print `byte0=` )
    ( nurl_print ( nurl_str_int ( string_get a 0 ) ) ) ( nurl_print `\n` )

    // Clear
    ( string_clear s )
    ( nurl_print `cleared len=` )
    ( nurl_print ( nurl_str_int ( string_len s ) ) ) ( nurl_print `\n` )

    ( string_free s )
    ( string_free n )
    ( string_free a )
    ( string_free b )
    ( string_free c )
    ^ 0
}
