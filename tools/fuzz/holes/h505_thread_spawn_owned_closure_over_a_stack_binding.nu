// H505: as h503, `thread_spawn_owned`: only `thread_spawn` was on the
// list, so the owned form took a closure over a `: ~` local to another
// thread (the fault depends on the thread running after the frame goes).
// Closed: as h503.
// v0.80.0: accepted; ran clean (timing-dependent).
$ `stdlib/std/thread.nu`

: Counter { i n i max }

@ start → v {
    : ~ Counter c @ Counter { 0 10 }
    : !Thread ThreadErr _f ( thread_spawn_owned \ → v { = . c n + . c n 1 } )
}

@ main → i {

    ( start )

    ^ 0
}
