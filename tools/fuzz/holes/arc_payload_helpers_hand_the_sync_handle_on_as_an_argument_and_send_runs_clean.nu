// arc_payload_helpers_hand_the_sync_handle_on_as_an_argument_and_send_runs_clean: a function handed an Arc's payload, on eight threads, hands it on, two calls deep, to a function that hands the payload's Channel field to a third as an argument, which sends on it. The payload is frozen but for what synchronises itself, and the send is made through the Channel, borrowed by value (agora #639 — refused before it as "hands 'first' the contents of Arc 'mine' to change"). Every send arrives.
// The control for arc_payload_helpers_hand_the_plain_field_on_as_an_argument_and_grow_it.
// map: §6.5 | A3 | runs-clean | - | a function handed an Arc's payload hands the Channel field on as a by-value argument, three calls deep, and sends on it: a change made through a self-synchronising field of a frozen payload (agora #639)
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

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( first ( arc_get [App] mine ) k )
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    : ~ i got 0
    : ~ b more T
    ~ more { ?? ( chan_try_recv [i] . ( arc_get [App] shared ) jobs ) { T x → { = got + got 1 } F → { = more F } } }
    ^ ? == got 24000 0 1
}
