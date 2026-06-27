// utf8_basic.nu — exercises the std/utf8 codepoint layer on real multi-byte
// text: café (2-byte é), € (3-byte), 😀 (4-byte), plus a deliberately broken
// sequence. Each check bumps `fails`; the program exits 0 iff all pass.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/utf8.nu`

@ main → i {
    : ~ i fails 0

    // "café" — 5 bytes, 4 scalars, last scalar é = U+00E9 = 233.
    ? != ( nurl_str_len `café` ) 5 { = fails + fails 1 } {}
    ? != ( utf8_len `café` ) 4 { = fails + fails 1 } {}
    ? ! ( utf8_valid `café` ) { = fails + fails 1 } {}
    ?? ( utf8_nth `café` 3 ) {
        T cp → { ? != cp 233 { = fails + fails 1 } {} }
        F _ → { = fails + fails 1 }
    }

    // "€" — U+20AC = 8364, one scalar, three bytes.
    ? != ( utf8_len `€` ) 1 { = fails + fails 1 } {}
    ? != ( nurl_str_len `€` ) 3 { = fails + fails 1 } {}
    ?? ( utf8_nth `€` 0 ) {
        T cp → { ? != cp 8364 { = fails + fails 1 } {} }
        F _ → { = fails + fails 1 }
    }

    // "😀" — U+1F600 = 128512, one scalar, four bytes.
    ? != ( utf8_len `😀` ) 1 { = fails + fails 1 } {}
    ? != ( nurl_str_len `😀` ) 4 { = fails + fails 1 } {}
    ?? ( utf8_nth `😀` 0 ) {
        T cp → { ? != cp 128512 { = fails + fails 1 } {} }
        F _ → { = fails + fails 1 }
    }

    // Codepoint-aware reverse: "abé" → "éba" (é stays intact).
    : String r ( utf8_reverse `abé` )
    ? != ( utf8_len ( string_data r ) ) 3 { = fails + fails 1 } {}
    ?? ( utf8_nth ( string_data r ) 0 ) {
        T cp → { ? != cp 233 { = fails + fails 1 } {} }  // first scalar is é
        F _ → { = fails + fails 1 }
    }
    ( string_free r )

    // Codepoint-aware substring: scalar 3, length 1 of "café" is "é".
    : String sub ( utf8_substr `café` 3 1 )
    ? != ( nurl_str_len ( string_data sub ) ) 2 { = fails + fails 1 } {}  // é is 2 bytes
    ? != ( utf8_len ( string_data sub ) ) 1 { = fails + fails 1 } {}
    ( string_free sub )

    // Round-trip: decode to scalars and re-encode → identical bytes.
    : ( Vec i ) cps ( utf8_codepoints `héllo€` )
    ? != ( vec_len [i] cps ) 6 { = fails + fails 1 } {}
    : String rt ( utf8_from_codepoints cps )
    ? == 0 ( nurl_str_eq ( string_data rt ) `héllo€` ) { = fails + fails 1 } {}
    ( string_free rt )
    ( vec_free [i] cps )

    // A malformed sequence: lead byte 0xC3 (195) followed by 'A' (not a
    // continuation byte) → invalid, and utf8_len reports -1.
    : String bad ( string_with_cap 4 )
    ( string_push_char bad 195 )
    ( string_push_char bad 65 )
    ? ( utf8_valid ( string_data bad ) ) { = fails + fails 1 } {}
    ? != ( utf8_len ( string_data bad ) ) -1 { = fails + fails 1 } {}
    ( string_free bad )

    ? == fails 0
    { ( nurl_print `utf8: all checks passed\n` ) }
    { ( nurl_print `utf8: FAILURES\n` ) }
    ^ ? == fails 0 0 1
}
