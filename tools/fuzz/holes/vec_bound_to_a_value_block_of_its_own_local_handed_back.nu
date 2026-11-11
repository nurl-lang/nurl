// vec_bound_to_a_value_block_of_its_own_local_handed_back: `: ( Vec String ) w { : ~ ( Vec String ) u … u }`, then `^ w`; the caller reads the Vec.
// Closed: a `:` binding's value block whose tail is a binding the block made is that binding to w's drop flag, as `: w u` is: w is a cursor over u, and `^ w` hands u's value to the caller (gen_let_or_struct, __let_blk_tail_name; agora #615). Read as a block, w was a borrow with no owner link while u kept a constant drop: the function freed what it handed back.
// main 0b31adec: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #615: a Vec bound to a value block of the block's own local, handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → ( Vec String ) {
    : ( Vec String ) w { : ~ ( Vec String ) u ( vec_new [String] ) ( vec_push [String] u ( string_from `an element string long enough for a heap buffer` ) ) u }
    ^ w
}

@ main → i {
    : ( Vec String ) v ( mk )
    ( nurl_println_int # i ( vec_len [String] v ) )
    ?? ( vec_get [String] v 0 ) { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    ^ 0
}
