// value_block_tail_spelled_like_the_target_sunk_first: `= s { : String s <fresh>  ( eat s )  s }`: the block-local, already handed to a sink, was stored into s (agora #806).
// Closed: gen_assign hands a value block's tail that is a block-local spelled like the target over by its slot, under the name `|s`; the walk reads `|s` as the spelling the block's frame closed, and a block's end row names its tail before that frame closes (agora #806).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #806: the block-local tail handed to a sink before it is the tail
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → v { ( nurl_println ( string_data x ) ) }

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `inner fresh string long enough for heap` ) )
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : String s ( string_from `inner fresh string long enough for heap` ) ( eat s ) s } = k + k 1 }
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data ( vec_at [String] vs 0 ) ) )
    ^ 0
}
