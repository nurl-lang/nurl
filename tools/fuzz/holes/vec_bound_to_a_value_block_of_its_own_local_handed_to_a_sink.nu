// vec_bound_to_a_value_block_of_its_own_local_handed_to_a_sink: `: ( Vec String ) w { : ~ ( Vec String ) u … u }`, then `( eat w )` with `eat` taking a `sink`.
// Closed: a `:` binding's value block whose tail is a binding the block made is that binding to w's drop flag, as `: w u` is: w is a cursor over u, and the sink takes u's value through it (gen_let_or_struct, __let_blk_tail_name; agora #615). Read as a block, w was a borrow with no owner link while u kept a constant drop.
// main 0b31adec: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #615: a Vec bound to a value block of the block's own local, handed to a sink
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink ( Vec String ) v → i { ^ # i ( vec_len [String] v ) }

@ main → i {
    : ( Vec String ) w { : ~ ( Vec String ) u ( vec_new [String] ) ( vec_push [String] u ( string_from `an element string long enough for a heap buffer` ) ) u }
    ( nurl_println_int ( eat w ) )
    ^ 0
}
