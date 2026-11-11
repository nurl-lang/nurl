// arc_payload_reader_grows_its_own_copies_of_a_bound_element_and_an_option_field_payload_runs_clean: a function handed an Arc's payload, on eight threads, binds an element of the payload's Vec to a name and grows a `vec_clone` of the Vec inside it, a copy of the same made by a function DEFINED BELOW it, and — inside a `??` over the payload's option field — a copy that function made of what the option holds. Every push lands in a copy the call owns and drops: the payload is never changed, so every call counts 2 + 2 + 2.
// The control for arc_payload_reader_grows_the_payload_of_an_option_field_bound_to_a_name and arc_payload_helper_grows_an_element_it_bound_to_a_name: a call with no summary yet (an instance of a generic first asked for here, a function defined below) is read out of its argument only where its final summary lends it — and out of what that argument was read out of only then.
// map: ThruOK.noShare | A3 | runs-clean | - | a function handed `( arc_get a )` grows a `vec_clone` of a field of an element it bound, and copies of it and of an option field's payload made by a function defined below: changes of copies, none of the frozen payload (agora #639, #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Inner { ( Vec i ) log i n }

: App { ( Vec Inner ) rows ? Inner slot ( Channel i ) jobs }

@ mkrow → Inner {
    : ( Vec i ) log ( vec_new [i] )
    ( vec_push [i] log 7 )
    ^ @ Inner { log 0 }
}

@ mkapp → App {
    : ( Vec Inner ) rows ( vec_new [Inner] )
    ( vec_push [Inner] rows ( mkrow ) )
    ^ @ App { rows @ ?Inner { T ( mkrow ) } ( chan_new [i] ) }
}

@ rd App a i k → i {
    : Inner r ( vec_at [Inner] . a rows 0 )
    // a library-made copy of the Vec inside the bound element
    : ( Vec i ) c ( vec_clone [i] . r log )
    ( vec_push [i] c k )
    // the same, made by a function defined below
    : ( Vec i ) d ( copy_of r )
    ( vec_push [i] d k )
    : ~ i got + ( vec_len [i] c ) ( vec_len [i] d )
    // a copy of what the option field holds
    ?? . a slot {
        T q → {
            : ( Vec i ) e ( copy_of q )
            ( vec_push [i] e k )
            = got + got ( vec_len [i] e )
        }
        F → {}
    }
    ^ got
}

@ copy_of Inner r → ( Vec i ) { ^ ( vec_clone [i] . r log ) }

@ reader ( Arc App ) mine Atomic sum i n → v {
    : ~ i k 0
    ~ < k n {
        : i before ( atomic_add sum ( rd ( arc_get [App] mine ) k ) )
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : Atomic sum ( atomic_new 0 )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine sum 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ ? == ( atomic_load sum ) 144000 0 1
}
