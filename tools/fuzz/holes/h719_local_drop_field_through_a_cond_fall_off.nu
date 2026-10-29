// H719: agora #178 — the same as the function's fall-off value (local_drop_field_through_a_cond_fall_off).
// Closed: a `?` / `??` arm that hands out a field of a value this function releases — a local, a `sink` parameter, a payload of one — is copied at the return, or refused when it cannot be copied (g_join_flends, __phi_lends_params_only; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d i n }

@ part i n b c → D {
    : H h @ H { @ D { ( mk ) } n }
    ? c . h d @ D { ( mk ) }
}

@ main → i {
    : D t ( part 1 T )
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
