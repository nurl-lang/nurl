// vec_of_sync_handles_grown_by_a_shared_closure: a closure four threads run hands its captured struct to a function that pushes a new Channel into the struct's Vec of Channels. An element of that Vec is a handle that synchronises itself, and sending on one is its own change (agora #639); the Vec that holds them is plain memory, reallocated under every thread reading it.
// Guard of #639's rule: a container of self-synchronising handles is not one.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helper pushes into its captured struct's Vec of Channels: the elements synchronise themselves, the Vec holding them does not (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec ( Channel i ) ) lanes i n }

@ widen App a i k → v {
    : b sent ( chan_send [i] ( vec_at [( Channel i )] . a lanes 0 ) k )
    ( vec_push [( Channel i )] . a lanes ( chan_new [i] ) )
}

@ main → i {
    : ( Vec ( Channel i ) ) lanes ( vec_new [( Channel i )] )
    ( vec_push [( Channel i )] lanes ( chan_new [i] ) )
    : App app @ App { lanes 1 }
    : ( @ v i ) work \ i k → v { ( widen app k ) }
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
    ^ ( vec_len [( Channel i )] . app lanes )
}
