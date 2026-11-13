// value_block_tail_spelled_like_the_target_in_a_loop: `= s { : String s <fresh>  s }` in a loop: the block-local s, spelled like the target, was dropped at the block's end and the freed value stored into s (agora #806).
// Closed: gen_assign hands a value block's tail that is a block-local spelled like the target over by its slot, under the name `|s`; the walk reads `|s` as the spelling the block's frame closed, and a block's end row names its tail before that frame closes (agora #806).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #806: a value block's fresh block-local tail spelled like the assign target, in a loop
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : String s ( string_from `inner fresh string long enough for heap` ) s } = k + k 1 }
    ( nurl_println ( string_data s ) )
    ^ 0
}
