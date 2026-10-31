// enum_payload_closure_signature: agora #129 — the same closure stored as an enum variant's payload (enum_payload_closure_signature).
// Closed: A struct literal field and an enum variant payload refuse a value whose type differs from the declared one across an option, result, slice or closure shape (__agg_shape_clash — the binding check's rule), and an enum payload refuses a different named type (__arg_named_struct_mismatch); agora #129.
// main: accepted; the program died with SIGSEGV.
// map: §2.11 | A2 | rejected | h914 | agora #129: the same closure as an enum variant's payload
$ `stdlib/core/string.nu`

@ mkg → ( @ i s ) { ^ \ s t → i { ^ ( nurl_str_len t ) } }

@ mki → ( @ i i ) { ^ \ i x → i { ^ + x 1 } }

: | E { V ( @ i i ) N }

@ main → i {
    : E e @ E { V ( mkg ) }
    ?? e { V h → ( nurl_println_int ( h 12345 ) ) N → {} }
    ^ 0
}
