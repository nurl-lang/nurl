// arc_payload_reader_grows_the_payload_of_an_option_field_bound_to_a_name: a function handed an Arc's payload matches the payload's option field (`?? . a slot { T r → … }`), binds the Vec inside what the option holds to a name (`: ( Vec i ) c . r log`) and pushes to the binding. Eight threads hold a clone of the Arc and read its payload with no lock, so every one of them grows the one buffer at once.
// The `??` payload binding is part of the field it was matched out of, and a handle bound out of it is the parameter's own — as the direct push `( vec_push [i] . r log k )` is, which main refused.
// main (before agora #646): ASan heap-use-after-free / double free — realloc of one buffer from several threads.
// map: ThruOK.noShare | A3 | rejected | - | a function handed `( arc_get a )` binds a Vec out of the payload `r` of `?? . a slot { T r → … }` over an option FIELD and pushes to the binding: a change of a frozen payload (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Inner { ( Vec i ) log i n }

: App { ? Inner slot ( Channel i ) jobs }

@ mkapp → App { ^ @ App { @ ?Inner { T @ Inner { ( vec_new [i] ) 0 } } ( chan_new [i] ) } }

@ grow App a i k → v {
    ?? . a slot {
        T r → {
            : ( Vec i ) c . r log
            ( vec_push [i] c k )
        }
        F → {}
    }
}

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
