// Passing a raw C-string `s` (i8*) where a `String` (managed) parameter is
// declared is silent UB (ABI-compatible, wrong representation) — must be a
// compile error. Convert with `string_from`.
$ `stdlib/core/string.nu`

@ takes_string String s → i { ^ ( string_len s ) }

@ main → i {
    : String x ( string_from `hello` )
    ^ ( takes_string ( string_data x ) )
}
