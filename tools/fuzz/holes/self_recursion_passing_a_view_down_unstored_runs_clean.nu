// self_recursion_passing_a_view_down_unstored_runs_clean: a self-recursive function hands back a Vec of its first parameter and passes the second down unread; the caller releases the second's String before it reads the result.
// Closed: the recursion's g_fn_rviews answer is its least fixed point (__bck_walk_scc): only the first argument, so its callers' results are not tied to the second.
// main 4f15689: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a self-recursive holder of its first view; the second, passed down, is released first
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ collect s text s label i depth → ( Vec s ) {
    ? == depth 0 {
        : ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h text )
        ^ h
    } {}
    ^ ( collect text label - depth 1 )
}

@ main → i {
    : String s ( string_from `the text that the result views, long enough for the heap` )
    : ~ ( Vec s ) r ( vec_new [s] )
    {
        : String lab ( string_from `a label built on the heap, long enough to matter` )
        = r ( collect ( string_data s ) ( string_data lab ) 2 )
    }
    ( nurl_println ( vec_at [s] r 0 ) )
    ^ 0
}
