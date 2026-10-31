// match_arm_selects_a_consumed_owner: agora #242 (formal's review) — `( consume a )`, then `: String u ?? o { T _ → a F → b }` and a read of `u`: a `??` arm that is a binding was read nowhere, so selecting the freed `a` was accepted (match_arm_selects_a_consumed_owner).
// Closed: gen_match records such an arm's read on its `endmatch-arm-edge` row, and bck_handle_match reads it from the arm's state.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.1 | A1 | rejected | - | agora #242: a `??` arm selecting an owner already consumed
$ `stdlib/core/string.nu`

@ consume sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : String b ( string_from `another heap string long enough for the heap` )
    : ?i o @ ?i { T ( string_len b ) }
    : i n ( consume a )
    : String u ?? o { T _ → a F → b }
    ^ + n ( string_len u )
}
