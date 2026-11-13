// closure_over_a_vec_of_views_of_a_local_crossing_a_thread_is_refused: a closure that captured by value a ( Vec s ) holding a view of a local String, handed to thread_spawn; the String is freed while the thread reads it
// Closed: agora #469, a closure's copy of a handle carries the views the handle's own storage holds (`\~v(…)`), and they may not cross.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §6.5 | A3 | rejected | - | agora #469: a Vec of views of a local crossing in a closure's handle copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter` )
    : ~ ( Vec s ) c ( vec_new [s] )
    ( vec_push [s] c ( string_data m ) )
    : ( @ v ) job \ → v { ( sleep_ms 50 ) ( nurl_print ( vec_at [s] c 0 ) ) ( nurl_print `\n` ) }
    : !Thread ThreadErr t ( thread_spawn job )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
