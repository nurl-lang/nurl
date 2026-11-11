// arc_payload_plain_field_of_a_sync_marked_struct_matched_out_of_a_holder_grown: eight threads each hold a struct with a clone of one Arc in it. The payload holds a Vec of `Tally`, a struct the program asserts `% Sync`, with a plain Vec field. An accessor handed the holder hands back that field of an element as an option; the reader matches it and pushes to it, directly — through no by-value `Tally` — on every thread at once.
// A program's own `% Sync` struct is not sealed: its fields are places of the payload like any other, and a view of one is a view of the frozen payload. (The mark vouches for changes made through a by-value `Tally`, agora #639 — not for its fields read out and changed beside it.)
// main (before agora #646): ASan double free.
// map: ThruOK.noShare | A3 | rejected | - | the `??` payload of an accessor handed a struct that holds the Arc — the plain Vec field of a `% Sync`-marked struct inside the payload — pushed to: a mark answers for changes through the marked value, not for its fields (agora #646)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Tally { ( Vec i ) v Atomic sum }

unsafe % Sync Tally {}

: App { ( Vec Tally ) ts i n }

@ mkapp → App {
    : ( Vec Tally ) ts ( vec_new [Tally] )
    ( vec_push [Tally] ts @ Tally { ( vec_new [i] ) ( atomic_new 0 ) } )
    ^ @ App { ts 0 }
}

: Hold { ( Arc App ) a i id }

@ vof Hold h i k → ?( Vec i ) {
    : App a ( arc_get [App] . h a )
    ?? ( vec_get [Tally] . a ts k ) { T t → { ^ @ ?( Vec i ) { T . t v } } F → {} }
    ^ @ ?( Vec i ) { F # ( Vec i ) 0 }
}

@ reader Hold mine i n → v {
    : ~ i k 0
    ~ < k n {
        ?? ( vof mine 0 ) { T p → { ( vec_push [i] p k ) } F → {} }
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
