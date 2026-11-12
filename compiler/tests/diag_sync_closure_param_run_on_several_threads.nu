// diag_sync_closure_param_run_on_several_threads.nu — a helper that
// spawns a thread per round of a loop, each running its closure
// parameter, runs that closure on several threads at once: what the
// caller's closure captures must be Sync, and it may not change it (the
// Sync-closure rule, as for a closure kept in an Arc). Asked Send alone,
// eight threads pushed to one captured Vec (Agora #713). The same holds
// for two spawns of it, for a helper that hands it on to such a one, and
// for par_map_index's `f`.
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ run8 ( @ v i ) f → v {
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i l 0
    ~ < l 8 {
        : i lane l
        : ( @ v ) body \ → v { ( f lane ) }
        ?? ( thread_spawn body ) { T th → { ( vec_push [Thread] ts th ) } F e → {} }
        = l + l 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
}

@ main → i {
    : ( Vec i ) acc ( vec_new [i] )
    ( run8 \ i lane → v { : ~ i k 0 ~ < k 3000 { ( vec_push [i] acc k ) = k + k 1 } } )
    ^ 0
}
