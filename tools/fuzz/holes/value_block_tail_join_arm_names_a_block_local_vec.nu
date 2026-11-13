// value_block_tail_join_arm_names_a_block_local_vec: a Vec filled in the block, named by the tail join's arm, in a loop (agora #807).
// Closed: a join that is its value block's tail publishes the block-local an arm lent, with the bit that says the arm ran; the block's `}` moves it into the join's value on that path, as an arm's own local moves (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #807: a tail join arm naming a block-local Vec (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : ~ ( Vec i ) s ( vec_new [i] )
    : ~ i k 0
    ~ < k 2 { = s { : ~ ( Vec i ) u ( vec_new [i] ) ( vec_push [i] u k ) ? > k 0 { u } { ( vec_new [i] ) } } = k + k 1 }
    ( nurl_println_int ( vec_len [i] s ) )
    ^ 0
}
