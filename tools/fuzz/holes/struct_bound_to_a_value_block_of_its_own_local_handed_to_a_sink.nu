// struct_bound_to_a_value_block_of_its_own_local_handed_to_a_sink: `: P e { : P p @ P { ( string_from … ) 2 } p }`, then `( eat e )` with `eat` taking a `sink`.
// Closed: a `:` binding's value block whose tail is a binding the block made is that binding to e's drop flag, as `: e p` is: e takes p's flag, and the sink takes the value from e (gen_let_or_struct, __let_blk_tail_name; agora #615). Read as a block, e was a borrow with no owner link while p kept a constant drop.
// main 0b31adec: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #615: a struct bound to a value block of the block's own local, handed to a sink
$ `stdlib/core/string.nu`

: P { String name i n }

@ eat sink P x → i { ^ + ( string_len . x name ) . x n }

@ main → i {
    : P e { : P p @ P { ( string_from `inner string long enough for a heap buffer` ) 2 } p }
    ( nurl_println_int ( eat e ) )
    ^ 0
}
