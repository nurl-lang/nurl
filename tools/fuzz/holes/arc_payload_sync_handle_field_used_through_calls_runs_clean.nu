// arc_payload_sync_handle_field_used_through_calls_runs_clean: a function handed an Arc's payload, two calls deep, sends on the payload's Channel field while a thread holding a clone receives from it. The payload is frozen but for what synchronises itself, and the send is made through the Channel, borrowed by value (agora #639 — refused before it as "hands 'deep' the contents of Arc 'held' to change").
// The control for arc_payload_helper_grows_the_plain_field_beside_its_sync_handle.
// map: §6.5 | A3 | runs-clean | - | a function handed an Arc's payload sends on its Channel field two calls deep while another thread receives: a change made through a self-synchronising field of a frozen payload (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log }

@ note App a i k → v { : b sent ( chan_send [i] . a jobs k ) }

@ deep App a i k → v { ( note a k ) }

@ main → i {
    : ( Arc App ) held ( arc_new [App] @ App { ( chan_new [i] ) ( vec_new [i] ) } )
    : ( Arc App ) theirs ( arc_clone [App] held )
    : Atomic got ( atomic_new 0 )
    : ( @ v ) body \ → v {
        : ~ i j 0
        ~ < j 2000 {
            ?? ( chan_recv [i] . ( arc_get [App] theirs ) jobs ) { T x → { : i before ( atomic_add got 1 ) } F → {} }
            = j + j 1
        }
    }
    ?? ( thread_spawn body ) {
        T th → {
            : ~ i j 0
            ~ < j 2000 { ( deep ( arc_get [App] held ) j ) = j + j 1 }
            : i joined ( thread_join th )
        }
        F _ → {}
    }
    ^ ? == ( atomic_load got ) 2000 0 1
}
