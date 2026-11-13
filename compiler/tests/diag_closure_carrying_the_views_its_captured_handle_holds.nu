// diag_closure_carrying_the_views_its_captured_handle_holds.nu — a closure
// that captured an owner of views by value holds a copy of its handle, and
// the views that handle's storage holds go wherever the closure goes
// (Agora #469, #467). A `( Vec s )` holding a view of a String, copied into
// a closure handed to another thread, still views the String this side
// frees; handed back out of a function, it still views the argument (or
// the local) it was given a view of. Each was taken for a closure holding
// nothing of anybody's. Each function below is refused.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: P { s w String o }

// Crossing to a thread, over a local String's view.
@ to_a_thread → v {
    : String m ( string_from `a message on the heap, long enough to matter` )
    : ~ ( Vec s ) c ( vec_new [s] )
    ( vec_push [s] c ( string_data m ) )
    : !Thread ThreadErr t ( thread_spawn \ → v { ( nurl_println ( vec_at [s] c 0 ) ) } )
    ?? t { T th → { : i _j ( thread_join th ) } F _ → {} }
}

// …over a copy of a parameter's Vec of views.
@ a_parameters_views ( Vec s ) msgs → v {
    : ( Vec s ) c ( vec_clone [s] msgs )
    : !Thread ThreadErr t ( thread_spawn \ → v { ( nurl_println ( vec_at [s] c 0 ) ) } )
    ?? t { T th → { : i _j ( thread_join th ) } F _ → {} }
}

// Handed back, over a view of its own local.
@ of_a_local → ( @ v ) {
    : String loc ( string_from `a heap string long enough to be on the heap for sure` )
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data loc ) )
    ^ \ → v { ( nurl_println ( vec_at [s] h 0 ) ) }
}

// Handed back over a view of the parameter: the caller's binding depends
// on the argument.
@ of_the_parameter String s → ( @ v ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ \ → v { ( nurl_println ( vec_at [s] h 0 ) ) }
}

@ run_after_the_argument_is_gone → v {
    : ~ ( @ v ) f \ → v {}
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = f ( of_the_parameter s )
    }
    ( f )
}

// …a struct's view field filled from the parameter.
@ in_a_struct String s → ( @ v ) {
    : P h @ P { ( string_data s ) ( string_from `owned` ) }
    ^ \ → v { ( nurl_println . h w ) }
}

@ struct_run_after_the_argument_is_gone → v {
    : ~ ( @ v ) f \ → v {}
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = f ( in_a_struct s )
    }
    ( f )
}

@ main → i {
    ^ 0
}
