// enum_temp_matched_in_a_loop_body: agora #155 — a call's enum matched unbound in a loop body: the next round released it again (enum_temp_matched_in_a_loop_body).
// Closed: the match temporary's scope drop clears its flag (gen_match, mem_emit_gated_drop; agora #155).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h650 | agora #155: a call's enum matched unbound in a loop body: the next round released it again
$ `stdlib/core/string.nu`

: P { String s i n }

: | E {
    V P
    NoVal
}

@ make i v → E { ^ @ E { V @ P { ( string_from `hello world, long enough for a heap buffer` ) v } } }

@ main → i {
    : ~ i n 0
    : ~ i acc 0
    ~ < n 100 {
        ?? ( make n ) {
            V p → { = acc + acc + . p n ( string_len . p s ) }
            NoVal → {}
        }
        = n + n 1
    }
    ( nurl_println_int acc )
    ^ 0
}
