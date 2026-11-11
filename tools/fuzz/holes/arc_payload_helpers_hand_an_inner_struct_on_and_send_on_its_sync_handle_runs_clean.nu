// arc_payload_helpers_hand_an_inner_struct_on_and_send_on_its_sync_handle_runs_clean: a function handed an Arc's payload, on eight threads, hands the payload's inner struct on to a second function as an argument, which sends on that struct's Channel — a field of a field of the payload. The payload is frozen but for what synchronises itself, and the send is made through the Channel, borrowed by value (agora #639 — refused before it as "hands 'first' the contents of Arc 'mine' to change"). Every send arrives.
// The control for arc_payload_helpers_hand_an_inner_struct_on_and_grow_its_plain_field.
// map: §6.5 | A3 | runs-clean | - | a function handed an Arc's payload hands its inner struct on by value to one that sends on the struct's Channel: a change made through a self-synchronising field of a field of a frozen payload (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Inner { ( Vec i ) v ( Channel i ) c }

: App { Inner in i n }

@ mkapp → App { ^ @ App { @ Inner { ( vec_new [i] ) ( chan_new [i] ) } 1 } }

@ second Inner n i k → v { : b sent ( chan_send [i] . n c k ) }

@ first App a i k → v { ( second . a in k ) }

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
    ~ more { ?? ( chan_try_recv [i] . . ( arc_get [App] shared ) in c ) { T x → { = got + got 1 } F → { = more F } } }
    ^ ? == got 24000 0 1
}
