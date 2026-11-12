// closure_parameter_spawned_once_changing_its_capture_runs_clean: a helper spawning one thread with its closure parameter, handed a closure that pushes to a captured Vec
// Guard for agora #713's fix: one thread running the closure may change what it captured.
// main dc7f5adf: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #713 guard: a closure parameter run on one thread may still change its capture
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ run1 ( @ v i ) f → v {
    : ( @ v ) body \ → v { ( f 0 ) }
    ?? ( thread_spawn body ) { T th → { : i j ( thread_join th ) } F e → {} }
}

@ main → i {
    : ( Vec i ) acc ( vec_new [i] )
    ( run1 \ i lane → v { : ~ i k 0 ~ < k 3000 { ( vec_push [i] acc k ) = k + k 1 } } )
    ^ 0
}
