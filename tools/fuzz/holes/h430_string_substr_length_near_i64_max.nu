// H430: `( string_substr s 2 9223372036854775807 )`: the clamp tested
// `start + len > slen`, which wraps negative for a length near i64 max, so
// the length stayed huge and the copy ran from a null buffer.
// Closed: the length is clamped against the room left (`slen - start`).
// v0.80.0: accepted; UndefinedBehaviorSanitizer reported a null memcpy.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_from `abcdef` )
    : String t ( string_substr s 2 9223372036854775807 )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
