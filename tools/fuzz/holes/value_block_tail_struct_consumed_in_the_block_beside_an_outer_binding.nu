// value_block_tail_struct_consumed_in_the_block_beside_an_outer_binding: `: P q { : P p @ P { … }  : i n ( eat_p p )  p }` with an outer p: the consumed struct was handed on (agora #629).
// Closed: a block's end row is translated before the block's frame closes, so the walk judges the tail by the binding the block spells it with, not the outer one of that name (agora #806, #629).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #629: a consumed struct block-local tail beside an outer binding (UAF on main)
$ `stdlib/core/string.nu`

: P { String a }

@ eat_p sink P x → i { ^ ( string_len . x a ) }

@ main → i {
    : ~ P p @ P { ( string_from `outer string long enough for a heap buffer` ) }
    : P q { : P p @ P { ( string_from `inner string long enough for a heap buffer` ) } : i n ( eat_p p ) p }
    ( nurl_println ( string_data . q a ) )
    ^ 0
}
