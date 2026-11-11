// shared_closure_recursive_helper_sends_on_the_sync_handle_runs_clean: a closure eight threads run hands its captured struct to a function that calls itself and then sends on the struct's Channel. Every change is made through the Channel, borrowed by value, at each depth: the handle's own (agora #639 — refused before it as "the closure changes 'app'"). Every send arrives.
// The control for shared_closure_recursive_helper_grows_the_plain_field_beside_the_sync_handle.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's recursive helper only sends on the Channel field: changes made through a self-synchronising handle, through the function's call of itself (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

@ rec App a i d i k → v {
    ? > d 0 { ( rec a - d 1 k ) } {}
    : b sent ( chan_send [i] . a jobs k )
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
        ( rec app 2 k )
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
    ^ ? == ( drain . app jobs ) 72000 0 1
}
