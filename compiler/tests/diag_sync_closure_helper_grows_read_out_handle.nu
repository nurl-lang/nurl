// diag_sync_closure_helper_grows_read_out_handle.nu — a change made
// through a handle read out of a parameter is a change of that parameter
// (docs/MEMORY.md §6.5; agora #646). A function a thread-shared closure
// hands its captured struct to pushes to an element of the struct's Vec
// of Vecs: the element handle is a copy, the buffer it grows is the one
// every thread running the closure reaches. Reading the element out is no
// change (thread_sync_handle_through_calls.nu).

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec ( Vec i ) ) rows i n }

// Grows the first row.
@ grow App a i k → v { ( vec_push [i] ( vec_at [( Vec i )] . a rows 0 ) k ) }

@ main → i {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( vec_new [i] ) )
    : App app @ App { rows 1 }
    : ( @ v i ) work \ i k → v { ( grow app k ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}
