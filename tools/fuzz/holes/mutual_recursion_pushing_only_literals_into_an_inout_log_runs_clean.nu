// mutual_recursion_pushing_only_literals_into_an_inout_log_runs_clean: two mutually recursive helpers take an inout log and a view; they push only a literal and never store the view. The view's String is released before the log is read.
// Closed: the two walks ask each other's g_fn_vkeeps answers; they settle them together as the least fixed point (__bck_walk_scc), which keeps nothing of the view in the log. The one walked second no longer answers "may".
// main 4f15689: accepted; ran clean.
// map: §2.7 | A2 | runs-clean | - | agora #370: mutually recursive helpers given an inout log and a view push only literals
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ tag_even inout ( Vec s ) log s w i n → v {
    ? == n 0 { ( vec_push [s] log `done` ) ^ } {}
    ( tag_odd log w - n 1 )
}

@ tag_odd inout ( Vec s ) log s w i n → v { ( tag_even log w n ) }

@ main → i {
    : ~ ( Vec s ) log ( vec_new [s] )
    {
        : String w ( string_from `a word built on the heap, long enough to matter` )
        ( tag_even log ( string_data w ) 3 )
    }
    ( nurl_println ( vec_at [s] log 0 ) )
    ^ 0
}
