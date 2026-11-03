// closure_returned_hands_a_captured_payload_to_a_sink: agora #463 — `^ \ → i { ?? x { T s → { ^ ( eat s ) } F → … } }`, called twice
// Closed: a payload read out of a returned closure's capture, handed to a `sink`, is handed a copy (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `^ \ → i { ?? x { T s → { ^ ( eat s ) } F → … } }`, called twice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ cap → ( @ i ) {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    ^ \ → i { ?? x { T s → { ^ ( eat s ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
