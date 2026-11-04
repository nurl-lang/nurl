// closure_local_hands_a_captured_payload_to_a_sink: agora #463 — `: ( @ i ) c \ → i { ?? x { T s → { ^ ( eat s ) } F → … } }`, called once
// Closed: a payload of a capture handed to a `sink` takes the capture over, as the capture itself handed there does (the consumed-capture rule) (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `: ( @ i ) c \ → i { ?? x { T s → { ^ ( eat s ) } F → … } }`, called once
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    : ( @ i ) c \ → i { ?? x { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ^ 0
}
