// self_recursion_with_an_inout_counter_runs_clean: a self-recursive function hands back a Vec of its text and counts in an inout Vec of ints; the caller pushes to the counter, then reads the result.
// Closed: the recursion's g_fn_rviews answer is its least fixed point (__bck_walk_scc): the result views the text, not the counter, so pushing to the counter ends nothing.
// main 4f15689: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a self-recursive holder of its text, given an inout counter its caller grows
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ walk s text inout ( Vec i ) seen i depth → ( Vec s ) {
    ( vec_push [i] seen depth )
    ? == depth 0 {
        : ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h text )
        ^ h
    } {}
    ^ ( walk text seen - depth 1 )
}

@ main → i {
    : String s ( string_from `the text that the result views, long enough for the heap` )
    : ~ ( Vec i ) seen ( vec_new [i] )
    : ( Vec s ) r ( walk ( string_data s ) seen 2 )
    ( vec_push [i] seen 99 )
    ( nurl_println ( vec_at [s] r 0 ) )
    ^ 0
}
