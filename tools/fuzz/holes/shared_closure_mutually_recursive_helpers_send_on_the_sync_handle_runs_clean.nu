// shared_closure_mutually_recursive_helpers_send_on_the_sync_handle_runs_clean: a closure eight threads run hands its captured struct to `ping`, which calls `pong` (defined below it), which sends on the struct's Channel and calls `ping` again. Round the cycle every change is made through the Channel, borrowed by value: the handle's own (agora #639 — refused before it as "the closure changes 'app'"). Every send arrives.
// The control for shared_closure_mutually_recursive_helpers_grow_the_plain_field_beside_the_sync_handle.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's helper calls a function below it that only sends on the Channel field and calls the helper back: changes made through a self-synchronising handle, round a cycle of two functions (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

@ ping App a i d i k → v {
    ? > d 0 { ( pong a - d 1 k ) } {}
}

@ pong App a i d i k → v {
    : b sent ( chan_send [i] . a jobs k )
    ( ping a d k )
}

@ drain ( Channel i ) ch → i {
    : ~ i n 0
    : ~ b more T
    ~ more { ?? ( chan_try_recv [i] ch ) { T x → { = n + n 1 } F → { = more F } } }
    ^ n
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v {
        ( ping app 2 k )
    }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc ( @ v i ) ) mine ( arc_clone [( @ v i )] shared )
        : ( @ v ) body \ → v {
            : ~ i j 0
            ~ < j 3000 {
                : ( @ v i ) run ( arc_get [( @ v i )] mine )
                ( run j )
                = j + j 1
            }
        }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ ? == ( drain . app jobs ) 48000 0 1
}
