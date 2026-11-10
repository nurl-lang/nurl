// inout_view_param_sent_to_a_thread: agora #466 — `: s msg x` of an inout view parameter, captured by a closure thread_spawn runs
// main c4d36651: accepted (a view crossing to another thread, which the rule for a non-inout view parameter refuses).
// map: §2.10 | A2 | rejected | - | agora #466: `: s msg x` of an inout view parameter, captured by a closure thread_spawn runs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ fire inout s x → v {
    : s msg x
    : !Thread ThreadErr r ( thread_spawn \ → v { ( nurl_println msg ) } )
    ?? r { T t → { ( thread_join t ) } F e → {} }
}

@ main → i {
    : String m ( string_from `a heap string long enough to be on the heap for sure` )
    : ~ s x ( string_data m )
    ( fire x )
    ^ 0
}
