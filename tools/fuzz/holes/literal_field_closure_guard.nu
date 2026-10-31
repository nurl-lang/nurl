// literal_field_closure_guard: agora #129 — a closure of the declared signature in a struct literal field: accepted (literal_field_closure_guard).
// Closed: A struct literal field and an enum variant payload refuse a value whose type differs from the declared one across an option, result, slice or closure shape (__agg_shape_clash — the binding check's rule), and an enum payload refuses a different named type (__arg_named_struct_mismatch); agora #129.
// main: accepted and ran clean (kept as a guard).
// map: §2.11 | A2 | runs-clean | h916 | agora #129: a closure of the declared signature in a struct literal field: accepted
$ `stdlib/core/string.nu`

@ mkg → ( @ i s ) { ^ \ s t → i { ^ ( nurl_str_len t ) } }

@ mki → ( @ i i ) { ^ \ i x → i { ^ + x 1 } }

: P { ( @ i i ) f }

@ main → i {
    : P p @ P { ( mki ) }
    : ( @ i i ) h . p f
    ( nurl_println_int ( h 41 ) )
    ^ 0
}
