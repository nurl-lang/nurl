// closure_run_after_its_thread_copy_took_the_capture: a closure bound to a name, handed to `thread_spawn` and then also run in the frame, moved one value out twice: once in each copy of its env.
// Closed: a copy of the env takes the captures over (the env it was copied from gives them up); the frame's run of the original stops with a panic instead (memory-safe).
// main's compiler: heap-use-after-free.
// map: §6.5 | A3 | runs-clean | h244 | closure given to thread and also run in frame: capture moved twice
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
}

@ main → i {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( eat r ) ( puts `ran` ) }
    : !Thread ThreadErr t ( thread_spawn f )
    ?? t { T th → ( thread_join th ) F e → {} }
    ( f )
    ^ 0
}
