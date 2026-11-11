// arc_payload_slice_in_a_struct_matched_out_of_a_holder_of_the_arc_written: eight threads each hold a struct with a clone of one Arc in it. A function handed the struct builds a Slice over the payload's Vec, wraps it in a struct of the program's own and hands that back as an option; the reader matches it and writes through the Slice — the frozen payload's elements, written by every thread at once.
// The payload binding's type (`Win`) sits nowhere in the Arc's payload, but it holds a view: a payload that holds views is taken for one of the frozen payload wherever its type reaches a window that checked code writes through (a `Slice`, a struct over a raw pointer with no drop hook).
// main (before agora #646): compiles; a race on the elements (no heap corruption for ASan to see).
// map: ThruOK.noShare | A3 | rejected | - | the `??` payload of a function handed a struct that holds the Arc — a struct holding a Slice over the payload's Vec — written through with `slice_put`: a window into a frozen payload (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: App { ( Vec i ) log ( Vec ( Vec i ) ) rows ( Channel i ) jobs }

@ mkapp → App {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( vec_new [i] ) )
    : ( Vec i ) log ( vec_new [i] )
    ( vec_push [i] log 1 )
    ( vec_push [i] log 2 )
    ^ @ App { log rows ( chan_new [i] ) }
}

: Win { ( Slice i ) w i tag }

: Hold { ( Arc App ) a i id }

@ win Hold h → ?Win {
    : App a ( arc_get [App] . h a )
    ^ @ ?Win { T @ Win { ( slice_from_vec [i] . a log ) 0 } }
}

@ reader Hold mine i n → v {
    : ~ i k 0
    ~ < k n {
        ?? ( win mine ) { T x → { ( slice_put [i] . x w 0 k ) } F → {} }
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
