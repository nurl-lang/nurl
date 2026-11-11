// shared_closure_helper_grows_its_own_copy_made_by_a_function_defined_below_it_runs_clean: a closure eight threads run hands its captured struct to a function that binds `( copy_of a )` and pushes to the binding, where `copy_of` — DEFINED BELOW the function — hands back a `vec_clone` of the struct's Vec field. Each call grows a copy of its own and drops it: the captured Vec is never changed, so every call finds its copy one long.
// The control for shared_closure_helper_grows_a_field_lent_by_a_function_defined_below_it: a binding of a call to a function with no summary yet is resolved against the callee's final lends, and a callee that lends nothing leaves the binding the caller's own.
// map: §6.5 | A3 | runs-clean | - | a thread-shared closure's helper binds the result of a function defined below it, which hands back a `vec_clone` of its parameter's Vec field, and pushes to the binding: a change of a copy, none of the capture (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

@ grow App a i k → i {
    : ( Vec i ) e ( copy_of a )
    ( vec_push [i] e k )
    ^ ( vec_len [i] e )
}

@ copy_of App a → ( Vec i ) { ^ ( vec_clone [i] . a log ) }

@ main → i {
    : App app ( mkapp )
    : Atomic ran ( atomic_new 0 )
    : ( @ v i ) work \ i k → v {
        : i before ( atomic_add ran ( grow app k ) )
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
