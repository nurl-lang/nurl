// closure_over_a_vec_of_views_run_by_a_closure_crossing_a_thread_is_refused: the thread's closure runs a closure that captured a ( Vec s ) holding a view of a local String
// Closed: agora #469, the views a captured closure's handle copies hold go with it.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §6.5 | A3 | rejected | - | agora #469: a nested closure's Vec of views crossing
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter` )
    : ~ ( Vec s ) c ( vec_new [s] )
    ( vec_push [s] c ( string_data m ) )
    : ( @ v ) inner \ → v { ( nurl_print ( vec_at [s] c 0 ) ) ( nurl_print `\n` ) }
    : ( @ v ) job \ → v { ( sleep_ms 50 ) ( inner ) }
    : !Thread ThreadErr t ( thread_spawn job )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
