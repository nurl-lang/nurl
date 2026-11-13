// value_block_tail_join_arm_names_a_reassigned_block_local: a `: ~` block-local given a new value, then named by the tail join's arm, in a loop (agora #807).
// Closed: a join that is its value block's tail publishes the block-local an arm lent, with the bit that says the arm ran; the block's `}` moves it into the join's value on that path, as an arm's own local moves (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #807: a tail join arm naming a reassigned block-local (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : ~ String u ( string_from `inner fresh string long enough for heap` ) = u ( string_from `second fresh string long enough for heap` ) ? > k 0 { u } { ( string_from `else` ) } } = k + k 1 }
    ( nurl_println ( string_data s ) )
    ^ 0
}
