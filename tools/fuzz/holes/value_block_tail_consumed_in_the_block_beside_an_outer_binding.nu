// value_block_tail_consumed_in_the_block_beside_an_outer_binding: `: String e { : String s <fresh>  : i n ( eat s )  s }` with an outer s: the tail was judged against the outer s, which nothing moved, and the consumed value was handed on (agora #629).
// Closed: a block's end row is translated before the block's frame closes, so the walk judges the tail by the binding the block spells it with, not the outer one of that name (agora #806, #629).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #629: a consumed block-local tail handed on beside an outer binding of its name (UAF on main)
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ eat2 sink String x sink String y → i { ^ + ( string_len x ) ( string_len y ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : String e { : String s ( string_from `inner string long enough for a heap buffer` ) : i n ( eat s ) s }
    ( nurl_println ( string_data e ) )
    ^ 0
}
