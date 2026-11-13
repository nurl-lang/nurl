// join_cursor_stored_into_a_literal_runs_clean: `: ~ cur ? k a b`, `@ H { cur 0 }`: the literal copies, a and b keep their own
// Kept: a cursor bound as a borrow of a join is copied where it is stored, and every source keeps and drops its own value (agora #824; main leaked the one copied).
// main 83059aae: accepted; LeakSanitizer: 56 bytes leaked in 2 allocations.
// map: §2.10 | A2 | runs-clean | - | agora #824: a join's cursor stored into a literal
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ main → i {
    : ~ ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ~ ( Vec i ) b ( vec_new [i] )
    : ~ i k 1
    : ~ ( Vec i ) cur ? > k 0 a b
    : ~ H q @ H { cur 0 }

    ( nurl_println_int ( vec_len [i] . q items ) )
    ^ 0
}
