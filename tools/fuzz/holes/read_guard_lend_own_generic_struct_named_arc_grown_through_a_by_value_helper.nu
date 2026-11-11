// read_guard_lend_own_generic_struct_named_arc_grown_through_a_by_value_helper: a program with no std/arc declares a generic struct of its own named `Arc` — a handle (`Arc_drop`) over a plain Vec — and keeps one in the value of an RwLocked. A function handed it by value, read out of a read guard's lend, pushes to the Vec, and eight threads hold read guards at once.
// Guard of agora #639's rule: what the thread rules grant an Arc — a change through a by-value one is the handle's own — is the standard library's promise, read off what the instance is (the generic struct it was made from, the file that declared that struct: __ty_std_arc), not off how its name is spelled.
// main: refused. A first cut of #639 read the name: ASan double free.
// map: ThruOK.noShare | A3 | rejected | - | a program's own generic struct named `Arc` (no std/arc), a handle over a plain Vec, read out of a read guard's lend and handed by value to a function that pushes to the Vec: an Arc is the standard library's, by what the instance is and not by its name (agora #639)
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Arc [T] { ( Vec T ) v }

@ Arc_drop [T] sink ( Arc T ) x → v {}

: App { ( Arc i ) bag i n }

@ grow ( Arc i ) a i k → v { ( vec_push [i] . a v k ) }

@ reader ( RwLocked App ) l i n → v {
    : ~ i k 0
    ~ < k n {
        : ( RGuard App ) g ( rw_read [App] l )
        ( grow . ( rguard_get [App] g ) bag k )
        = k + k 1
    }
}

@ main → i {
    : ( RwLocked App ) shared ( rw_new [App] @ App { @ ( Arc i ) { ( vec_new [i] ) } 1 } )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        ?? ( thread_spawn \ → v { ( reader shared 3000 ) } ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
