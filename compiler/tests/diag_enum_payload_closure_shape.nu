// diag_enum_payload_closure_shape.nu — an enum variant's payload given a
// closure of another signature (agora #129). Both closures lower to
// `{ ptr, ptr }`, so the boxed payload used to be called through the
// declared signature: an int read as a string pointer.
$ `stdlib/core/string.nu`

@ mkg → ( @ i s ) { ^ \ s t → i { ^ ( nurl_str_len t ) } }

: | E { V ( @ i i ) N }

@ main → i {
    : E e @ E { V ( mkg ) }
    ?? e { V h → ( nurl_println_int ( h 12345 ) ) N → {} }
    ^ 0
}
