// value_block_tail_join_arm_bound_then_sunk: `: String t { : String u <fresh>  ? c { u } { … } }  ( eat t )`: the sink released the block-local, then its scope end released it again (agora #807).
// Closed: a join that is its value block's tail publishes the block-local an arm lent, with the bit that says the arm ran; the block's `}` moves it into the join's value on that path, as an arm's own local moves (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #807: a tail join arm naming a block-local, bound and sunk (UAF on main)
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : i k 1
    : String t { : String u ( string_from `inner fresh string long enough for heap` ) ? > k 0 { u } { ( string_from `else branch string long enough for heap` ) } }
    ( nurl_println_int ( eat t ) )
    ^ 0
}
