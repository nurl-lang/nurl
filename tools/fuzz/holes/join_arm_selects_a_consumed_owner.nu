// join_arm_selects_a_consumed_owner: agora #242 (formal's review) — `( consume a )`, then `: String u ? c a b` and a read of `u`: a `?` arm's value is read on the join's edge rows, which no walk visited, so selecting the freed `a` was accepted (join_arm_selects_a_consumed_owner).
// Closed: bck_handle_cond reads each arm's value where its arm ends, from that arm's state.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.1 | A1 | rejected | - | agora #242: a `?` arm selecting an owner already consumed
$ `stdlib/core/string.nu`

@ consume sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : String b ( string_from `another heap string long enough for the heap` )
    : i c ( string_len b )
    : i n ( consume a )
    : String u ? == c 44 a b
    ^ + n ( string_len u )
}
