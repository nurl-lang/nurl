// diag_frozen_lend_own_struct_named_arc.nu — an Arc is the standard
// library's, by what the instance is and not by how its name is spelled
// (docs/MEMORY.md §6.5; agora #639). This program has no std/arc and
// declares a generic struct of its own named `Arc`, a handle over a plain
// Vec. A change through a by-value borrow of the library's Arc is the
// handle's own; through this one it is a change of what it was read out
// of — here a read guard's lend, which is frozen.

$ `stdlib/std/rwlock.nu`
$ `stdlib/core/vec.nu`

: Arc [T] { ( Vec T ) v }

@ Arc_drop [T] sink ( Arc T ) x → v {}

: App { ( Arc i ) bag i n }

@ grow ( Arc i ) a i k → v { ( vec_push [i] . a v k ) }

@ main → i {
    : ( RwLocked App ) shared ( rw_new [App] @ App { @ ( Arc i ) { ( vec_new [i] ) } 1 } )
    : ( RGuard App ) g ( rw_read [App] shared )
    ( grow . ( rguard_get [App] g ) bag 3 )
    ^ 0
}
