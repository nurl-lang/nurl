// value_block_tail_consumed_in_the_block_returned_beside_a_param: `^ { : String s <fresh>  : i n ( eat s )  s }` beside a parameter s: the consumed block-local was returned (agora #629).
// Closed: a block's end row is translated before the block's frame closes, so the walk judges the tail by the binding the block spells it with, not the outer one of that name (agora #806, #629).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #629: a consumed block-local tail returned beside a parameter of its name (UAF on main)
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ eat2 sink String x sink String y → i { ^ + ( string_len x ) ( string_len y ) }

@ f String s → String {
    ^ { : String s ( string_from `inner string long enough for a heap buffer` ) : i n ( eat s ) s }
}

@ main → i {
    : String r ( f ( string_from `p` ) )
    ( nurl_println ( string_data r ) )
    ^ 0
}
