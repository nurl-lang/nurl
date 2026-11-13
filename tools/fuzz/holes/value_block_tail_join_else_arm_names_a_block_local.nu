// value_block_tail_join_else_arm_names_a_block_local: the else arm names the block-local: `= s { : String u <fresh>  ? c { … } { u } }` in a loop (agora #807).
// Closed: a join that is its value block's tail publishes the block-local an arm lent, with the bit that says the arm ran; the block's `}` moves it into the join's value on that path, as an arm's own local moves (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #807: a tail join else arm naming a block-local (UAF on main)
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : String u ( string_from `inner fresh string long enough for heap` ) ? > k 5 { ( string_from `then` ) } { u } } = k + k 1 }
    ( nurl_println ( string_data s ) )
    ^ 0
}
