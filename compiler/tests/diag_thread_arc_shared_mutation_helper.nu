// diag_thread_arc_shared_mutation_helper.nu — the same race with the
// mutation one call deep.
//
// Moving the `vec_push` into a helper must not move it out of the
// check, or the diagnostic teaches "wrap it in a function" as the cure
// for a data race. The compiler carries a per-function summary
// (`g_fn_arc_mut`): a body that mutates the contents of an `arc_get`
// result is recorded, and a thread closure that CALLS such a function
// is rejected exactly as one that mutates inline.
//
// The summary is inferred in codegen order, like the sink and escape
// summaries, so a helper defined above its caller is seen.

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

// Mutates the contents of whatever Arc it is handed.
@ push_all ( Arc ( Vec i ) ) a → v {
    : ( Vec i ) v ( arc_get [( Vec i )] a )
    : ~ i k 0
    ~ < k 2000 { ( vec_push [i] v k ) = k + k 1 }
}

@ main → i {
    : ( Vec i ) d ( vec_new [i] )
    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )

    : ( @ v ) w1 \ → v { ( push_all a ) }

    : !Thread ThreadErr r1 ( thread_spawn w1 )
    ?? r1 { T t → { ( thread_join t ) } F e → { ( nurl_print `spawn fail\n` ) } }
    ^ 0
}
