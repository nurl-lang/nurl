// sink_enum_payload_field_returned: agora #178 — a field of a `sink` enum parameter's payload returned through a `??` arm (sink_enum_payload_field_returned).
// Closed: a `?` / `??` arm that hands out a field of a value this function releases — a local, a `sink` parameter, a payload of one — is copied at the return, or refused when it cannot be copied (g_join_flends, __phi_lends_params_only; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h716 | agora #178: a field of a `sink` enum parameter's payload returned through a `??` arm
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ part sink G g → String { ^ ?? g { V p → . p s Nil → ( mk ) } }

@ main → i {
    : String t ( part @ G { V @ P { ( mk ) 1 } } )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
