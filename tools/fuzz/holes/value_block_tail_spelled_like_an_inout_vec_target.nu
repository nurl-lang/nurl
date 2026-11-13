// value_block_tail_spelled_like_an_inout_vec_target: `= v { : ~ ( Vec i ) v ( vec_new [i] ) … v }` with v an `inout` parameter: the block's own v got no handover, so the block's end freed its buffer under the caller's Vec (agora #626).
// Closed: a value block's tail that is a block-local spelled like the target is handed over by its slot (`|v`, agora #806). Naming the outer v after such a block stays refused (the value-block scope rule).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #626: a Vec block-local spelled like an inout target as the block's tail (UAF on main)
$ `stdlib/core/vec.nu`

@ re inout ( Vec i ) v → v { = v { : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 5 ) v } }

@ main → i {
    : ~ ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    ( re a )
    ( vec_push [i] a 6 )
    ( nurl_println_int ( vec_len [i] a ) )
    ( nurl_println_int ( vec_at [i] a 0 ) )
    ^ 0
}
