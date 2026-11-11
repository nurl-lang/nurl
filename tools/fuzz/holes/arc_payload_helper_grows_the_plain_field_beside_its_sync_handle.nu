// arc_payload_helper_grows_the_plain_field_beside_its_sync_handle: a function handed an Arc's payload sends on the payload's Channel field and pushes to the plain Vec beside it, while a thread holding a clone reads that Vec. The send is the Channel's own change (agora #639 accepts it behind an Arc); the push changes a frozen payload.
// Guard of #639's rule on the Arc side: only the change made through the self-synchronising field is excused.
// map: §6.5 | A3 | rejected | - | a function handed an Arc's payload sends on its Channel field and pushes to the Vec beside it: the payload stays frozen but for what synchronises itself (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log }

@ note App a i k → v {
    : b sent ( chan_send [i] . a jobs k )
    ( vec_push [i] . a log k )
}

@ main → i {
    : ( Arc App ) held ( arc_new [App] @ App { ( chan_new [i] ) ( vec_new [i] ) } )
    : ( Arc App ) theirs ( arc_clone [App] held )
    : ( @ v ) body \ → v {
        : ~ i j 0
        : ~ i seen 0
        ~ < j 200000 { = seen + seen ( vec_len [i] . ( arc_get [App] theirs ) log ) = j + j 1 }
    }
    ?? ( thread_spawn body ) {
        T th → {
            : ~ i j 0
            ~ < j 200000 { ( note ( arc_get [App] held ) j ) = j + j 1 }
            : i joined ( thread_join th )
        }
        F _ → {}
    }
    ^ 0
}
