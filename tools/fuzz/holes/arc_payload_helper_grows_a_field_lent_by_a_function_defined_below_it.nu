// arc_payload_helper_grows_a_field_lent_by_a_function_defined_below_it: a function handed an Arc's payload binds `( pick a )` and pushes to the binding, where `pick` — DEFINED BELOW the function — hands back the payload's Vec field (`^ . a log`), a lend of its parameter. Eight threads each hold a clone of the Arc and run the function at once, so every one of them grows the one buffer.
// Guard of agora #646's derived edges: a binding of a call to a function with no summary yet is noted and resolved at the module's end against the callee's final lends, so the push through it is a change of the parameter the callee lent it out of. The payload stays frozen.
// map: §6.5 | A3 | rejected | - | a function handed an Arc's payload binds the result of a function defined below it, which lends its parameter's Vec field, and pushes to the binding: the payload stays frozen (agora #646)
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

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( grow ( arc_get [App] mine ) k )
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
