// arc_payload_generic_pair_matched_out_of_a_holder_of_the_arc_grown: eight threads each hold a struct with a clone of one Arc in it. An accessor handed the struct hands back an element of the payload's `Vec ( Pair i ( Vec i ) )` as an option; the reader matches it and pushes to the pair's Vec — the frozen payload's own, grown by every thread at once.
// The payload's type is an instance of a generic of two arguments: whether it sits in the Arc's payload is asked of the type arguments exactly as the instance was written (`Pair__i64__Vec__i64` is not split at its `__`).
// main (before agora #646): ASan double free.
// map: ThruOK.noShare | A3 | rejected | - | the `??` payload of an accessor handed a struct that holds the Arc — a `( Pair i ( Vec i ) )` element of the payload — its Vec pushed to: a two-argument generic instance inside a frozen payload (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Pair [A B] { A fst B snd }

: App { ( Vec ( Pair i ( Vec i ) ) ) prs i n }

@ mkapp → App {
    : ( Vec ( Pair i ( Vec i ) ) ) prs ( vec_new [( Pair i ( Vec i ) )] )
    ( vec_push [( Pair i ( Vec i ) )] prs @ ( Pair i ( Vec i ) ) { 1 ( vec_new [i] ) } )
    ^ @ App { prs 0 }
}

: Hold { ( Arc App ) a i id }

@ pr Hold h i k → ?( Pair i ( Vec i ) ) {
    : App a ( arc_get [App] . h a )
    ^ ( vec_get [( Pair i ( Vec i ) )] . a prs k )
}

@ reader Hold mine i n → v {
    : ~ i k 0
    ~ < k n {
        ?? ( pr mine 0 ) { T p → { ( vec_push [i] . p snd k ) } F → {} }
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
