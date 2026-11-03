// closure_local_hands_a_captured_option_to_a_sink: agora #463 — `: ( @ i ) c \ → i { ^ ( eat x ) }`, `x` a `?String`, `eat sink ?String`
// Closed: an option capture the body hands to a `sink` moves into the environment, as a String capture does (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `: ( @ i ) c \ → i { ^ ( eat x ) }`, `x` a `?String`, `eat sink ?String`
$ `stdlib/core/string.nu`

@ eat sink ? String o → i { ?? o { T s → { ^ ( string_len s ) } F → { ^ 0 } } }

@ main → i {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    : ( @ i ) c \ → i { ^ ( eat x ) }
    ( nurl_println_int ( c ) )
    ^ 0
}
