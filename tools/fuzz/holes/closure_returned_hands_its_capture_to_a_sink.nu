// closure_returned_hands_its_capture_to_a_sink: agora #463 — `^ \ → i { ^ ( eat x ) }`, `eat sink String`, called twice
// Closed: a returned closure keeps its captures for its next call: a `sink` handed one is handed a copy, as `^ x` in the body hands one back (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `^ \ → i { ^ ( eat x ) }`, `eat sink String`, called twice
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ cap → ( @ i ) {
    : String x ( string_from `a String local long enough for the heap` )
    ^ \ → i { ^ ( eat x ) }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
