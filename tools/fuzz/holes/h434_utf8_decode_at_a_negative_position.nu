// H434: `( utf8_decode_at b -2 )` and `( utf8_decode s -40 )`: the only
// range test was `pos >= n`, so a negative position read before the
// buffer.
// Closed: one unsigned compare puts a negative position out of range too.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/utf8.nu`

@ main → i {
    : String s ( string_from `hello` )
    : Utf8Dec d ( utf8_decode_at ( string_bytes s ) -2 )
    : Utf8Dec e ( utf8_decode ( string_data s ) -40 )
    ^ + . d cp . e cp
}
