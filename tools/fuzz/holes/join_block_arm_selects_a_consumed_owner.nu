// join_block_arm_selects_a_consumed_owner: agora #274 — `( consume a )`, then `: String u ? c { : i z 1 a } { b }` and a read of `u`: a block arm's tail reached no row of the walk, so selecting the freed `a` was accepted (join_block_arm_selects_a_consumed_owner).
// Closed: gen_block_expr records a value block's binding tail as a read on its `endblock` row, and the walk checks it from the block's own state before its scope closes.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.1 | A1 | rejected | - | agora #274: a `?` block arm whose tail selects an owner already consumed
$ `stdlib/core/string.nu`

@ consume sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : String b ( string_from `another heap string long enough for the heap` )
    : i c ( string_len b )
    : i n ( consume a )
    : String u ? == c 44 { : i z 1 a } { b }
    ^ + n ( string_len u )
}
