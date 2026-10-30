// local_join_in_option_fall_off: agora #184 — an option literal over a local's `?` as the function's fall-off value (local_join_in_option_fall_off).
// Closed: a returned option or result literal whose payload is a `?` / `??` that lent this function's own value copies it, as `^ ?` does; only a lend of the caller's value is answered per call (__phi_lends_params_only; agora #184).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h771 | agora #184: an option literal over a local's `?` as the function's fall-off value
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part b c → ?String {
    : String x ( mk )
    @ ?String { T ? c x ( mk ) }
}

@ main → i {
    : ?String t ( part T )
    ( nurl_println_int ?? t { T s → ( string_len s ) F → 0 } )
    ^ 0
}
