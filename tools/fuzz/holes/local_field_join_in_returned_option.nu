// local_field_join_in_returned_option: agora #184 — the same with a local struct's field (local_field_join_in_returned_option).
// Closed: a returned option or result literal whose payload is a `?` / `??` that lent this function's own value copies it, as `^ ?` does; only a lend of the caller's value is answered per call (__phi_lends_params_only; agora #184).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h769 | agora #184: the same with a local struct's field
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part b c → ?String {
    : P q @ P { ( mk ) 1 }
    ^ @ ?String { T ? c . q s ( mk ) }
}

@ main → i {
    : ?String t ( part T )
    ( nurl_println_int ?? t { T s → ( string_len s ) F → 0 } )
    ^ 0
}
