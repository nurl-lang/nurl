// holder_returned_whole_through_a_block_arm_runs_clean: AGORA-929 guard — `^ ? c { h } h2` with nothing taken out of `h`: the block-form arm hands it on whole, accepted
// map: §2.1 | A2 | runs-clean | - | AGORA-929 guard: a block-form join arm handing on an intact holder
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf }

@ f b c → Holder {
    : Holder h @ Holder { ( vec_new [u] ) }
    : Holder h2 @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 3 )
    ^ ? c { h } h2
}

@ main → i {
    : Holder r ( f T )
    ( vec_push [u] . r buf # u 1 )
    ( nurl_println_int ( vec_len [u] . r buf ) )
    ^ 0
}
