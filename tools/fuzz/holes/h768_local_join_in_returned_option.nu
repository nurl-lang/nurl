// H768: agora #184 — an option literal returned with a `?` over a local String as its payload (local_join_in_returned_option).
// Closed: a returned option or result literal whose payload is a `?` / `??` that lent this function's own value copies it, as `^ ?` does; only a lend of the caller's value is answered per call (__phi_lends_params_only; agora #184).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

: | E {
    S String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part b c → ?String {
    : String x ( mk )
    ^ @ ?String { T ? c x ( mk ) }
}

@ main → i {
    : ?String t ( part T )
    ( nurl_println_int ?? t { T s → ( string_len s ) F → 0 } )
    ^ 0
}
