// diag_thread_arc_payload_matched_out_of_holder.nu — an Arc's payload is
// frozen wherever the Arc is held (docs/MEMORY.md §6.5; agora #646). A
// function handed a struct that holds the Arc hands back an element of the
// payload's Vec as an option; the `??` arm's binding is a view of the
// frozen payload, and pushing to it grows a buffer every thread holding a
// clone reads.

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec ( Vec i ) ) rows i n }

: Hold { ( Arc App ) a i id }

@ row Hold h i k → ?( Vec i ) {
    : App a ( arc_get [App] . h a )
    ^ ( vec_get [( Vec i )] . a rows k )
}

@ reader Hold mine i k → v {
    ?? ( row mine 0 ) {
        T p → { ( vec_push [i] p k ) }
        F → {}
    }
}

@ main → i {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( vec_new [i] ) )
    : Hold h @ Hold { ( arc_new [App] @ App { rows 1 } ) 7 }
    ( reader h 3 )
    ^ 0
}
