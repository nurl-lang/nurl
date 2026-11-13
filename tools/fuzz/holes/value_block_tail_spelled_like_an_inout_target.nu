// value_block_tail_spelled_like_an_inout_target: `= s { : String s <fresh>  s }` with s an `inout` parameter: the block's own s, spelled like the target, got no handover, so the block's end released it and the caller's slot was given the freed value (agora #626).
// Closed: a value block's tail that is a block-local spelled like the target is handed over by its slot (`|s`, agora #806), whatever the target is.
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #626: a block-local spelled like an inout target as the block's tail (UAF on main)
$ `stdlib/core/string.nu`

@ setit inout String s → v { = s { : String s ( string_from `inner string long enough for a heap buffer` ) s } }

@ main → i {
    : ~ String a ( string_from `outer string long enough for a heap buffer` )
    ( setit a )
    ( nurl_println ( string_data a ) )
    ^ 0
}
