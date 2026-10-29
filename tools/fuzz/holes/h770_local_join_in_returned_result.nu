// H770: agora #184 — a result literal returned with a `?` over a local String (local_join_in_returned_result).
// Closed: a returned option or result literal whose payload is a `?` / `??` that lent this function's own value copies it, as `^ ?` does; only a lend of the caller's value is answered per call (__phi_lends_params_only; agora #184).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part b c → !String i {
    : String x ( mk )
    ^ @ !String i { T ? c x ( mk ) }
}

@ main → i {
    : !String i t ( part T )
    ( nurl_println_int ?? t { T s → ( string_len s ) F e → e } )
    ^ 0
}
