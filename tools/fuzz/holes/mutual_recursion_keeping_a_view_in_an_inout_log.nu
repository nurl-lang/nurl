// mutual_recursion_keeping_a_view_in_an_inout_log: two mutually recursive helpers take an inout log and a view; the base case pushes the view into the log, whose String is released before the log is read.
// Guard: the fixed point of the two walks (__bck_walk_scc) keeps the view in the log: the caller's log is tied to it.
// main 4f15689: rejected.
// map: §2.7 | A2 | rejected | - | agora #370: mutually recursive helpers keep a view in an inout log through their base case
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ tag_even inout ( Vec s ) log s w i n → v {
    ? == n 0 { ( vec_push [s] log w ) ^ } {}
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
