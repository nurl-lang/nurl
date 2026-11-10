// block_local_handed_to_an_inout_parameter_by_a_value_block: `@ re inout ( Vec i ) v → v { = v { : ~ ( Vec i ) w ( vec_new [i] ) ( vec_push [i] w 5 ) w } }`, the caller reads its argument after.
// Closed: an assignment's value block whose tail is a binding is that binding, as `= w u` is: u, of a scope that ends before w's, dies first, so its value moves to w (gen_assign; agora #574). Read as a block, w kept a borrow of u past u's end.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #574: a block-local handed to an inout parameter by a value block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ re inout ( Vec i ) v → v { = v { : ~ ( Vec i ) w ( vec_new [i] ) ( vec_push [i] w 5 ) w } }

@ main → i {
    : ~ ( Vec i ) z ( vec_new [i] )
    ( vec_push [i] z 9 )
    ( re z )
    ( nurl_println_int # i ( vec_len [i] z ) )
    ^ 0
}
