// local_struct_field_through_a_cond_returned: agora #178 — a local struct's field returned through a `?` (local_struct_field_through_a_cond_returned).
// Closed: a `?` / `??` arm that hands out a field of a value this function releases — a local, a `sink` parameter, a payload of one — is copied at the return, or refused when it cannot be copied (g_join_flends, __phi_lends_params_only; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h713 | agora #178: a local struct's field returned through a `?`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part i n b c → String {
    : P p @ P { ( mk ) n }
    ^ ? c . p s ( mk )
}

@ main → i {
    : String t ( part 1 T )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
