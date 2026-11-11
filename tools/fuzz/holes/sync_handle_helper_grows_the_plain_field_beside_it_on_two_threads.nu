// sync_handle_helper_grows_the_plain_field_beside_it_on_two_threads: a closure four threads run hands its captured struct to a function that sends on the struct's Channel and pushes to the plain Vec beside it. The send is the Channel's own change, under its own lock (agora #639 accepts it, wherever the Channel is read out of); the push grows one buffer from every thread at once.
// Guard of #639's rule: the question "does this type synchronise itself" is asked of each parameter a change is made through — the Channel the helper hands to chan_send — never of the struct the handle sits in.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helper sends on its captured struct's Channel and pushes to the Vec beside it: only the change made through the self-synchronising handle is the handle's own (agora #639)
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
    : App app @ App { ( chan_new [i] ) ( vec_new [i] ) }
    : ( @ v i ) work \ i k → v { ( note app k ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : ( Arc ( @ v i ) ) mine ( arc_clone [( @ v i )] shared )
        : ( @ v ) body \ → v {
            : ~ i j 0
            ~ < j 2000 {
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
    ^ ( vec_len [i] . app log )
}
