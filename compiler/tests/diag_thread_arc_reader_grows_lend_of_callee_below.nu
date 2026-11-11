// diag_thread_arc_reader_grows_lend_of_callee_below.nu — a function
// defined below its caller is judged by the summary it ends with, on the
// Arc side as in a shared closure (docs/MEMORY.md §6.5; agora #639,
// #646). `r` is an element of the payload's Vec and `vec_of` hands back
// the Vec inside it: what `tally` grows is the Arc's own buffer. Had
// `vec_of` handed back a copy, the push would be `tally`'s own business
// (thread_sync_copy_made_by_a_callee.nu).

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: Inner { ( Vec i ) v i n }

: App { ( Vec Inner ) ins i n }

@ mkapp → App {
    : ( Vec Inner ) ins ( vec_new [Inner] )
    ( vec_push [Inner] ins @ Inner { ( vec_new [i] ) 0 } )
    ^ @ App { ins 1 }
}

@ tally App x i k → v {
    : Inner r ( vec_at [Inner] . x ins 0 )
    : ( Vec i ) c ( vec_of r )
    ( vec_push [i] c k )
}

@ main → i {
    : ( Arc App ) held ( arc_new [App] ( mkapp ) )
    ( tally ( arc_get [App] held ) 5 )
    ^ 0
}

@ vec_of Inner r → ( Vec i ) { ^ . r v }
