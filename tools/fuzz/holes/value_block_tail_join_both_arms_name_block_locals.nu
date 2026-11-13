// value_block_tail_join_both_arms_name_block_locals: both arms name block-locals: `= s { : String u … : String w … ? c { u } { w } }` in a loop (agora #807).
// Closed: a join that is its value block's tail publishes the block-local an arm lent, with the bit that says the arm ran; the block's `}` moves it into the join's value on that path, as an arm's own local moves (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #807: both tail join arms naming block-locals (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 3 { = s { : String u ( string_from `inner fresh string long enough for heap` ) : String w ( string_from `second fresh string long enough for heap` ) ? == k 1 { u } { w } } = k + k 1 }
    ( nurl_println ( string_data s ) )
    ^ 0
}
