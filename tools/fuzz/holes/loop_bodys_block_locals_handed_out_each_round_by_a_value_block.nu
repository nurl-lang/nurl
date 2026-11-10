// loop_bodys_block_locals_handed_out_each_round_by_a_value_block: the same over three rounds: each round's value replaces the last one, which is released.
// Closed: an assignment's value block whose tail is a binding is that binding, as `= w u` is: u, of a scope that ends before w's, dies first, so its value moves to w (gen_assign; agora #574). Read as a block, w kept a borrow of u past u's end.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #574: a loop body's block-locals handed out each round by a value block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ re inout ( Vec i ) v → v { = v { : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 5 ) v } }

@ main → i {
    : ~ ( Vec i ) w ( vec_new [i] )
    : ~ i k 0
    ~ < k 3 {
        = w { : ~ ( Vec i ) u ( vec_new [i] ) ( vec_push [i] u k ) u }
        = k + k 1
    }
    ( nurl_println_int # i ( vec_len [i] w ) )
    ^ 0
}
