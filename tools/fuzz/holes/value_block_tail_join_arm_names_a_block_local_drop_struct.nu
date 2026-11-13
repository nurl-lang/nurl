// value_block_tail_join_arm_names_a_block_local_drop_struct: a `% Drop` struct block-local named by the tail join's arm, in a loop (agora #807).
// Closed: a join that is its value block's tail publishes the block-local an arm lent, with the bit that says the arm ran; the block's `}` moves it into the join's value on that path, as an arm's own local moves (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #807: a tail join arm naming a block-local % Drop struct (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

: D { String n }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ main → i {
    : ~ D s @ D { ( string_from `outer string long enough for a heap buffer` ) }
    : ~ i k 0
    ~ < k 2 { = s { : D u @ D { ( string_from `inner fresh string long enough for heap` ) } ? > k 0 { u } { @ D { ( string_from `second fresh string long enough for heap` ) } } } = k + k 1 }
    ( nurl_println ( string_data . s n ) )
    ^ 0
}
