// closure_parameter_spawned_at_two_sites_changing_its_capture_is_refused: a helper spawning two threads, each running its closure parameter, handed a closure that pushes to a captured Vec
// Closed: agora #713, two detaches capturing one parameter run it on several threads.
// main dc7f5adf: accepted (a data race on the Vec: two threads push to it with no lock).
// map: §6.5 | A3 | rejected | - | agora #713: a closure parameter two detaches capture is run on several threads, so it may not change what it captured
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ run2 ( @ v i ) f → v {
    : ( @ v ) b1 \ → v { ( f 1 ) }
    : ( @ v ) b2 \ → v { ( f 2 ) }
    ?? ( thread_spawn b1 ) { T t1 → {
            ?? ( thread_spawn b2 ) { T t2 → { : i j2 ( thread_join t2 ) } F e → {} }
            : i j1 ( thread_join t1 )
        } F e → {} }
}

@ main → i {
    : ( Vec i ) acc ( vec_new [i] )
    ( run2 \ i lane → v { : ~ i k 0 ~ < k 3000 { ( vec_push [i] acc k ) = k + k 1 } } )
    ^ 0
}
