// value_block_tail_consumed_in_the_block_handed_to_a_sink: `( eat { : String s <fresh>  : i n ( eat s )  s } )` with an outer s: the consumed block-local was handed to a second sink (agora #629).
// Closed: a block's end row is translated before the block's frame closes, so the walk judges the tail by the binding the block spells it with, not the outer one of that name (agora #806, #629).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #629: a consumed block-local tail as a sink argument beside an outer binding (UAF on main)
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : i r ( eat { : String s ( string_from `inner string long enough for a heap buffer` ) : i n ( eat s ) s } )
    ( nurl_println_int r )
    ^ 0
}
