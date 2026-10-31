// match_block_arm_selects_a_consumed_owner: agora #274 — the `??` form: `( consume a )`, then `: String u ?? o { T _ → { : i z 1 a } F → b }` and a read of `u` (match_block_arm_selects_a_consumed_owner).
// Closed: the block arm's tail is read on its `endblock` row (gen_block_expr) and checked from the block's state (bck_walk_seq).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.1 | A1 | rejected | - | agora #274: a `??` block arm whose tail selects an owner already consumed
$ `stdlib/core/string.nu`

@ consume sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : String b ( string_from `another heap string long enough for the heap` )
    : ?i o @ ?i { T ( string_len b ) }
    : i n ( consume a )
    : String u ?? o { T _ → { : i z 1 a } F → b }
    ^ + n ( string_len u )
}
