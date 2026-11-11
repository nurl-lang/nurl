// arc_payload_own_handle_holding_a_plain_vec_grown_through_a_by_value_helper: a struct of the program's own that is a handle (`Bag_drop`) and holds a plain Vec is read out of an Arc's payload and handed, by value, to a function that pushes to that Vec. Eight threads hold a clone of the Arc, so every one of them grows the one buffer with no lock.
// Guard of agora #639's rule: a change through a by-value parameter is the handle's own only where the handle synchronises itself. One nobody marked does so by what it is made of — every field a number, an Arc, a type asserted `% Sync` (__ty_selfsync) — and being a handle is not that.
// main: refused. A first cut of #639 took every handle not held in an rcbox: ASan double free.
// map: ThruOK.noShare | A3 | rejected | - | a program's own handle (a drop hook) holding a plain Vec, read out of `( arc_get a )` and handed by value to a function that pushes to the Vec: a handle synchronises itself only where every part of it does (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Bag { ( Vec i ) v }

@ Bag_drop sink Bag x → v {}

: App { ( Channel i ) jobs Bag bag i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) @ Bag { ( vec_new [i] ) } 1 } }

@ grow Bag j i k → v { ( vec_push [i] . j v k ) }

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
