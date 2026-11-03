// join_of_static_holders_returned_runs_clean: a join of holders of static literals handed back.
// The shape the fix must keep.
// main 4d57d596: runs clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a join of holders of static literals handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ ok String s i c → ( Vec s ) {
    : ( Vec s ) a ( vec_new [s] )
    ( vec_push [s] a `one` )
    : ( Vec s ) b ( vec_new [s] )
    ( vec_push [s] b `two` )
    ^ ? == c 0 a b
}

@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( ok s 0 )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
