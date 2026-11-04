// closure_local_hands_a_captured_payload_to_a_sink_twice: agora #463 — `: ( @ i ) c \ → i { ?? x { T s → { ^ ( eat s ) } … } }`, called twice
// Closed: the closure takes over the capture whose payload it hands to a `sink`; the body marks the capture taken in its env when it hands the payload on, so a second call, using the capture again, stops with a clean panic instead of reading freed memory (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `: ( @ i ) c \ → i { ?? x { T s → { ^ ( eat s ) } … } }`, called twice
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    : ( @ i ) c \ → i { ?? x { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
