// loop_bodys_block_local_handed_out_by_a_value_block: `~ < k 1 { = w2 { : ~ ( Vec i ) u ( vec_new [i] ) ( vec_push [i] u 1 ) u } … }`, then `w2` read after the loop.
// Closed: an assignment's value block whose tail is a binding is that binding, as `= w u` is: u, of a scope that ends before w's, dies first, so its value moves to w (gen_assign; agora #574). Read as a block, w kept a borrow of u past u's end.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #574: a loop body's block-local handed out by a value block to a binding outside the loop
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) w2 ( vec_new [i] )
    : ~ i k 0
    ~ < k 1 {
        = w2 { : ~ ( Vec i ) u ( vec_new [i] ) ( vec_push [i] u 1 ) u }
        = k + k 1
    }
    ( nurl_println_int # i ( vec_len [i] w2 ) )
    ^ 0
}
