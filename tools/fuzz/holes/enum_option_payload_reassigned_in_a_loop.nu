// enum_option_payload_reassigned_in_a_loop: agora #155 — an enum binding with an option payload reassigned in a loop (enum_option_payload_reassigned_in_a_loop).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer (every replaced payload).
// map: §7.6 | A2 | runs-clean | h643 | agora #155: an enum binding with an option payload reassigned in a loop
$ `stdlib/core/string.nu`

: | E {
    Opt ? String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ E e @ E { Opt @ ?String { T ( mk ) } }
    : ~ i n 0
    ~ < n 5 {
        = e @ E { Opt @ ?String { T ( mk ) } }
        = n + n 1
    }
    = e @ E { NoVal }
    ^ 0
}
