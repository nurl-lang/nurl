// closure_over_a_clone_of_a_vec_of_views_parameter_crossing_a_thread_is_refused: a function spawns a thread over a closure that captured ( vec_clone msgs ) of its ( Vec s ) parameter; the caller frees the String the views point into
// Closed: agora #469, what the copy holds is what the parameter holds, its caller's storage.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §6.5 | A3 | rejected | - | agora #469: a clone of a parameter's Vec of views crossing
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ launch ( Vec s ) msgs → !Thread ThreadErr {
    : ( Vec s ) c ( vec_clone [s] msgs )
    ^ ( thread_spawn \ → v { ( sleep_ms 50 ) ( nurl_print ( vec_at [s] c 0 ) ) ( nurl_print `\n` ) } )
}

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter` )
    : ~ ( Vec s ) v ( vec_new [s] )
    ( vec_push [s] v ( string_data m ) )
    : !Thread ThreadErr t ( launch v )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
