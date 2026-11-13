// value_block_tail_join_arm_spelled_like_the_target_in_a_loop: `= s { : String s <fresh>  ? c { s } { … } }` in a loop: the arm lent the block-local, the block's scope end released it, and s held the freed value (agora #807).
// Closed: a join that is its value block's tail publishes the block-local an arm lent, with the bit that says the arm ran; the block's `}` moves it into the join's value on that path, as an arm's own local moves (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #807: a tail join arm naming a block-local spelled like the target (UAF on main)
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : String s ( string_from `inner fresh string long enough for heap` ) ? > k 0 { s } { ( string_from `else branch` ) } } = k + k 1 }
    ( nurl_println ( string_data s ) )
    ^ 0
}
