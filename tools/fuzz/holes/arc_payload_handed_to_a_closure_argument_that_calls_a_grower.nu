// arc_payload_handed_to_a_closure_argument_that_calls_a_grower: a function handed an Arc's payload hands it on to its closure parameter, and the closure handed in calls a named function that pushes to the payload's plain Vec. Eight threads each hold a clone of the Arc and run the function at once, so every one of them grows the one buffer.
// Guard of #639's rule on the Arc side: the closure argument's own callee changes plain data, two hand-overs away from the payload.
// map: §6.5 | A3 | rejected | - | a function handed an Arc's payload hands it to a closure argument that calls a named function pushing to the plain Vec field: the payload stays frozen (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

@ grow App y → v { ( vec_push [i] . y log 1 ) }

@ with App x ( @ v App ) f → v { ( f x ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( with ( arc_get [App] mine ) \ App y → v { ( grow y ) } )
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
