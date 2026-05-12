// Test: MVP 2 String operations
$ `stdlib/core/string.nu`

@ main → i {
    // with_cap + push
    : String s ( string_with_cap 64 )
    ( string_push_str s `hello world` )
    ( nurl_print ( string_data s ) ) ( nurl_print `\n` )

    // concat
    : String a ( string_from `foo` )
    : String b ( string_from `bar` )
    : String c ( string_concat a b )
    ( nurl_print ( string_data c ) ) ( nurl_print `\n` )

    // starts_with / ends_with / contains
    ( nurl_print ? ( string_starts_with s `hello` ) `sw1\n` `sw0\n` )
    ( nurl_print ? ( string_starts_with s `world` ) `sw1\n` `sw0\n` )
    ( nurl_print ? ( string_ends_with   s `world` ) `ew1\n` `ew0\n` )
    ( nurl_print ? ( string_ends_with   s `hello` ) `ew1\n` `ew0\n` )
    ( nurl_print ? ( string_contains    s `lo wo` ) `ct1\n` `ct0\n` )
    ( nurl_print ? ( string_contains    s `zzz`   ) `ct1\n` `ct0\n` )

    // substr
    : String m ( string_substr s 6 5 )
    ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
    : String m2 ( string_substr s 0 5 )
    ( nurl_print ( string_data m2 ) ) ( nurl_print `\n` )
    // out-of-range clamping
    : String m3 ( string_substr s 9 99 )
    ( nurl_print ( string_data m3 ) ) ( nurl_print `\n` )

    ( string_free s )
    ( string_free a )
    ( string_free b )
    ( string_free c )
    ( string_free m )
    ( string_free m2 )
    ( string_free m3 )
    ^ 0
}
