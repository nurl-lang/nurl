// literal_field_closure_signature: agora #129 — a struct literal stores a `( @ i s )` closure in a `( @ i i )` field; both lower to `{ ptr, ptr }`, the call through the field reads an int as a string (literal_field_closure_signature).
// Closed: A struct literal field and an enum variant payload refuse a value whose type differs from the declared one across an option, result, slice or closure shape (__agg_shape_clash — the binding check's rule), and an enum payload refuses a different named type (__arg_named_struct_mismatch); agora #129.
// main: accepted; the program died with SIGSEGV.
// map: §2.11 | A2 | rejected | h913 | agora #129: a struct literal stores a `( @ i s )` closure in a `( @ i i )` field; both lower to `{ ptr, ptr }` and the call through the field reads an int as a string
$ `stdlib/core/string.nu`

@ mkg → ( @ i s ) { ^ \ s t → i { ^ ( nurl_str_len t ) } }

@ mki → ( @ i i ) { ^ \ i x → i { ^ + x 1 } }

: P { ( @ i i ) f }

@ main → i {
    : P p @ P { ( mkg ) }
    : ( @ i i ) h . p f
    ( nurl_println_int ( h 12345 ) )
    ^ 0
}
