// arc_payload_handed_to_a_function_value_read_out_of_a_struct_that_grows_it: a function handed an Arc's payload calls a function value it reads out of a struct field (`: ( @ v App ) g . o f`) on the payload, and that closure pushes to the payload's plain Vec. Eight threads each hold a clone of the Arc and run the function at once, so every one of them grows the one buffer.
// Guard of #639's rule on the Arc side: a call through a function value read out of a struct names no callee whose summary could excuse it; the payload stays frozen.
// map: §6.5 | A3 | rejected | - | a function handed an Arc's payload runs a function value read out of a struct field on it, which pushes to the plain Vec field: the payload stays frozen (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs ( Vec i ) log i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( vec_new [i] ) 1 } }

: Ops { ( @ v App ) f i tag }

@ with App x Ops o → v {
    : ( @ v App ) g . o f
    ( g x )
}

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : Ops o @ Ops { \ App y → v { ( vec_push [i] . y log 1 ) } 1 }
        ( with ( arc_get [App] mine ) o )
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
