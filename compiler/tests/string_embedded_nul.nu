// Test: Vec[u]-backed String preserves embedded NUL bytes inside [0, len).
// `string_data` still truncates at the first NUL (C-string contract), but
// `string_len` and the underlying buffer carry the full sequence.

$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_with_cap 8 )
    ( string_push_char s 65 )  // 'A'
    ( string_push_char s 0 )  // embedded NUL
    ( string_push_char s 66 )  // 'B'
    ( string_push_char s 0 )  // another NUL
    ( string_push_char s 67 )  // 'C'

    // string_len counts ALL bytes between [0, len) — NULs included.
    ( nurl_print_int ( string_len s ) )  // 5

    // string_data truncates at first NUL — C-string contract.
    ( nurl_print ( string_data s ) )  // "A"
    ( nurl_print `\n` )

    // string_get sees individual bytes regardless of NULs.
    ( nurl_print_int ( string_get s 0 ) )  // 65
    ( nurl_print_int ( string_get s 1 ) )  // 0
    ( nurl_print_int ( string_get s 2 ) )  // 66
    ( nurl_print_int ( string_get s 3 ) )  // 0
    ( nurl_print_int ( string_get s 4 ) )  // 67

    ( string_free s )
    ^ 0
}
