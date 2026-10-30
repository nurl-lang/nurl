// H917: agora #129 — a closure of the declared signature as an enum payload: accepted (enum_payload_closure_guard).
// Closed: A struct literal field and an enum variant payload refuse a value whose type differs from the declared one across an option, result, slice or closure shape (__agg_shape_clash — the binding check's rule), and an enum payload refuses a different named type (__arg_named_struct_mismatch); agora #129.
// main: accepted and ran clean (kept as a guard).
$ `stdlib/core/string.nu`

@ mkg → ( @ i s ) { ^ \ s t → i { ^ ( nurl_str_len t ) } }

@ mki → ( @ i i ) { ^ \ i x → i { ^ + x 1 } }

: | E { V ( @ i i ) N }

@ main → i {
    : E e @ E { V ( mki ) }
    ?? e { V h → ( nurl_println_int ( h 41 ) ) N → {} }
    ^ 0
}
