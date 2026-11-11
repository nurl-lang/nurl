// shared_closure_helper_hands_its_parameter_to_a_closure_argument_that_only_reads_runs_clean: a closure eight threads run hands its captured struct to a function that hands it on to its closure parameter, and the closure handed in only reads the length of the struct's plain Vec. Nothing is changed, so nothing races: the count of rounds comes out whole.
// The control for shared_closure_helper_hands_its_parameter_to_a_closure_argument_that_grows_it.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's helper hands its parameter to a closure argument that only reads the plain Vec field: no change of the capture (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App {
    : ( Vec i ) log ( vec_new [i] )
    ( vec_push [i] log 7 )
    ^ @ App { ( chan_new [i] ) log 1 }
}

@ with App x ( @ i App ) f → i { ^ ( f x ) }

@ main → i {
    : App app ( mkapp )
    : Atomic ran ( atomic_new 0 )
    : ( @ v i ) work \ i k → v {
        : i before ( atomic_add ran ( with app \ App y → i { ^ ( vec_len [i] . y log ) } ) )
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
    ^ ? == ( atomic_load ran ) 24000 0 1
}
