// shared_closure_helpers_hand_the_sync_handle_on_as_an_argument_and_send_runs_clean: a closure eight threads run hands its captured struct on, two calls deep, to a function that hands the struct's Channel field to a third as an argument, which sends on it. The change is made through a Channel borrowed by value: the handle's own, wherever it was read out of (agora #639 — refused before it as "the closure changes 'app'"). Every send arrives.
// The control for shared_closure_helpers_hand_the_plain_field_on_as_an_argument_and_grow_it.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's helpers hand the Channel field on as a by-value argument, three calls deep, and send on it: a change made through a self-synchronising handle (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

@ third ( Channel i ) c i k → v { : b sent ( chan_send [i] c k ) }

@ second App a i k → v { ( third . a jobs k ) }

@ first App a i k → v { ( second a k ) }

@ drain ( Channel i ) ch → i {
    : ~ i n 0
    : ~ b more T
    ~ more { ?? ( chan_try_recv [i] ch ) { T x → { = n + n 1 } F → { = more F } } }
    ^ n
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v {
        ( first app k )
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
    ^ ? == ( drain . app jobs ) 24000 0 1
}
