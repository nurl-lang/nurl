// shared_closure_helper_grows_a_field_lent_by_a_function_defined_below_it: a thread-shared closure hands its captured struct to a function that binds `( pick a )` and pushes to the binding, where `pick` — DEFINED BELOW the function — hands back the struct's Vec field (`^ . a log`), a lend of its parameter. The closure sits in a struct in an Arc that eight threads run it out of, so every one of them grows the one buffer at once.
// Guard of agora #646's derived edges: a binding of a call to a function with no summary yet is noted and resolved at the module's end against the callee's final lends, so the push through it is a change of the parameter the callee lent it out of.
// map: §6.5 | A3 | rejected | - | a thread-shared closure's helper binds the result of a function defined below it, which lends its parameter's Vec field, and pushes to the binding: a change of the capture (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

@ grow App a i k → v {
    : ( Vec i ) e ( pick a )
    ( vec_push [i] e k )
}

@ pick App a → ( Vec i ) { ^ . a log }

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
        ( grow app k )
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
