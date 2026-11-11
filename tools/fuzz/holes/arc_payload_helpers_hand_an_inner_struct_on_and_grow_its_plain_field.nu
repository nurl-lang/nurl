// arc_payload_helpers_hand_an_inner_struct_on_and_grow_its_plain_field: a function handed an Arc's payload hands the payload's inner struct on to a second function as an argument, which pushes to that struct's plain Vec — a field of a field of the payload, beside the inner struct's Channel. Eight threads each hold a clone of the Arc and run the function at once, so every one of them grows the one buffer.
// Guard of #639's rule on the Arc side: the by-value parameter the change is made through is a plain struct that merely holds a Channel; the payload stays frozen.
// map: §6.5 | A3 | rejected | - | a function handed an Arc's payload hands its inner struct on by value to one that pushes to the struct's plain Vec, beside its Channel: a field of a field of a frozen payload (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Inner { ( Vec i ) v ( Channel i ) c }

: App { Inner in i n }

@ mkapp → App { ^ @ App { @ Inner { ( vec_new [i] ) ( chan_new [i] ) } 1 } }

@ second Inner n i k → v { ( vec_push [i] . n v k ) }

@ first App a i k → v { ( second . a in k ) }

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
