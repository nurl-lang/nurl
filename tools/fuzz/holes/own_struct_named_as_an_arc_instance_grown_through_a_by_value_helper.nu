// own_struct_named_as_an_arc_instance_grown_through_a_by_value_helper: a struct of the program's own is NAMED `Arc__Bag` — the compiler's spelling of `( Arc Bag )` — and holds a plain Vec. Read out of an Arc's payload and handed by value to a function that pushes to its Vec, on eight threads. Every rule that asks what a type is reads its name up to the first `__`: this one read as an Arc, a handle that synchronises itself.
// main: refused at the `arc_get` (the change summary charged the argument's root). With agora #639's rule the name alone made the change the handle's own: ASan double free. A struct's, an enum's or a trait's name holding `__` past its leading underscores is refused where it is declared.
// map: §6.5 | A3 | rejected | - | a struct of the program's own named `Arc__Bag`, the spelling of the instance `( Arc Bag )`, read as an Arc by the thread rules: a type's name holds no `__` past its leading underscores (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Arc__Bag { ( Vec i ) v }

: App { ( Channel i ) jobs Arc__Bag bag i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) @ Arc__Bag { ( vec_new [i] ) } 1 } }

@ grow Arc__Bag j i k → v { ( vec_push [i] . j v k ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ( grow . ( arc_get [App] mine ) bag k )
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
