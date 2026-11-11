// arc_payload_element_matched_out_of_a_holder_of_the_arc_grown: eight threads each hold a struct with a clone of one Arc in it. A function handed the struct reads the Arc's payload and hands back an element of its Vec of Vecs as an option; the reader matches it and pushes to the payload binding — the frozen payload's own row, grown by every thread at once.
// The lending call is handed a holder of the Arc, not the Arc: its `??` payload is parked as a view of the frozen payload where its type sits in the payload's type tree (here `( Vec i )`, an element of `rows`), as one out of `( arc_get a )` itself always was.
// main (before agora #646): ASan double free.
// map: ThruOK.noShare | A3 | rejected | - | the `??` payload of an accessor handed a struct that holds the Arc — an element of the payload's Vec of Vecs — pushed to: a change of a frozen payload reached through its holder (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) log ( Vec ( Vec i ) ) rows ( Channel i ) jobs }

@ mkapp → App {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( vec_new [i] ) )
    : ( Vec i ) log ( vec_new [i] )
    ( vec_push [i] log 1 )
    ( vec_push [i] log 2 )
    ^ @ App { log rows ( chan_new [i] ) }
}

: Hold { ( Arc App ) a i id }

@ row Hold h i k → ?( Vec i ) {
    : App a ( arc_get [App] . h a )
    ^ ( vec_get [( Vec i )] . a rows k )
}

@ reader Hold mine i n → v {
    : ~ i k 0
    ~ < k n {
        ?? ( row mine 0 ) { T p → { ( vec_push [i] p k ) } F → {} }
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : Hold mine @ Hold { ( arc_clone [App] shared ) t }
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
