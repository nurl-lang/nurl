// value_block_join_arm_tail_viewing_a_local_outlives_it_rejected: `: v ? c { : t ( vec_at outer 0 ) t } ( vec_new )`, then `outer` freed and `v` read: an arm block's tail that views something hands on what it views, so v borrows outer
// main 191e572: refused (compiler/tests/diag_borrow_block_local_value.nu). Read as the closed binding `|t` inside the join, v borrowed nothing; pinned.
// map: §7.6 | A2 | rejected | - | agora #823: a value block whose tail binding views something hands on what it views — in a join arm too; only a tail owning fresh storage is that binding
$ `stdlib/core/vec.nu`

@ arm ( Vec ( Vec i ) ) o0 b c → i {
    : ( Vec ( Vec i ) ) outer ( vec_clone [( Vec i )] o0 )
    : ( Vec i ) v ? c ( vec_new [i] ) { : ( Vec i ) t ( vec_at [( Vec i )] outer 0 ) t }
    ( vec_free [( Vec i )] outer )
    ^ ( vec_len [i] v )
}

@ main → i { ^ 0 }
