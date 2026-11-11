// arc_payload_helpers_hand_the_plain_field_on_as_an_argument_and_grow_it: a function handed an Arc's payload hands it on, two calls deep, to a function that hands the payload's plain Vec field — the one beside its Channel — to a third as an argument, which pushes to it. Eight threads each hold a clone of the Arc and run the function at once, so every one of them grows the one buffer.
// Guard of #639's rule on the Arc side: the by-value parameter the change is made through is a Vec, which does not synchronise itself; the payload stays frozen.
// map: §6.5 | A3 | rejected | - | a function handed an Arc's payload hands the plain Vec field beside the Channel on as a by-value argument, three calls deep, and pushes to it: the payload stays frozen (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

@ third ( Vec i ) w i k → v { ( vec_push [i] w k ) }

@ second App a i k → v { ( third . a log k ) }

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
    ^ 0
}
