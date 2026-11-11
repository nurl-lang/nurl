// shared_closure_helpers_hand_the_plain_field_on_as_an_argument_and_grow_it: a thread-shared closure hands its captured struct on, two calls deep, to a function that hands the struct's plain Vec field — the one beside its Channel — to a third as an argument, which pushes to it. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// Guard of #639's rule: the by-value parameter the change is made through is a Vec, which does not synchronise itself, so the change is one of what the Vec was read out of.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helpers hand the plain Vec field beside the Channel on as a by-value argument, three calls deep, and push to it: a change of the capture (agora #639)
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

: Holder { ( @ v i ) f i tag }

@ hit ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) g . h f
    : ~ i j 0
    ~ < j n {
        ( g j )
        = j + j 1
    }
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v {
        ( first app k )
    }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v { ( hit mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
