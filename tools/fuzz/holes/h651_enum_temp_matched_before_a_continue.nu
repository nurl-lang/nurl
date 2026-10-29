// H651: agora #155 — the same with a continue in the arm (enum_temp_matched_before_a_continue).
// Closed: the match temporary's scope drop clears its flag (gen_match, mem_emit_gated_drop; agora #155).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
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
        = n + n 1
        ?? ( make n ) {
            V p → {
                ? == 0 % . p n 3 { continue } {}
                = acc + acc + . p n ( string_len . p s )
            }
            NoVal → {}
        }
    }
    ( nurl_println_int acc )
    ^ 0
}
