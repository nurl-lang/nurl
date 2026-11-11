// arc_payload_mutually_recursive_helpers_send_on_the_sync_handle_runs_clean: a function handed an Arc's payload, on eight threads, calls `ping`, which calls `pong` (defined below it), which sends on the payload's Channel and calls `ping` again. The payload is frozen but for what synchronises itself, and round the cycle every change is made through the Channel, borrowed by value (agora #639 — refused before it as "hands 'ping' the contents of Arc 'mine' to change"). Every send arrives.
// The control for arc_payload_mutually_recursive_helpers_grow_the_plain_field_beside_the_sync_handle.
// map: §6.5 | A3 | runs-clean | - | a function handed an Arc's payload calls a function below it that only sends on the Channel field and calls it back: changes made through a self-synchronising field of a frozen payload, round a cycle of two functions (agora #639)
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

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( ping ( arc_get [App] mine ) 2 k )
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
    ^ ? == got 48000 0 1
}
