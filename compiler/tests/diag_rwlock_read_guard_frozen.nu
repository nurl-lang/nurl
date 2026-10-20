// diag_rwlock_read_guard_frozen.nu — what a read guard lends is frozen.
//
// Readers of an RwLocked hold one value at the same time; a reader that
// wrote through its view would race every other reader. RGuard is marked
// `% Frozen` (stdlib/core/marker.nu), so the compiler follows what
// rguard_get lends — into a slice of it, through a helper, into a binding
// — and rejects each write where it is made, as it does for an Arc's
// payload: slice_put, a container mutator, a function of the program's
// that changes its argument. The same write through a write guard
// compiles.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rwlock.nu`

: Page { ( Vec u ) data }

@ bytes_of ( RGuard Page ) g → ( Slice u ) { ^ ( slice_from_vec [u] . ( rguard_get [Page] g ) data ) }

// A helper of the program's that changes what it is handed.
@ zero_first ( Vec u ) v → v { ( vec_put [u] v 0 0 ) }

@ main → i {
    : ( RwLocked Page ) l ( rw_new [Page] @ Page { ( vec_zeroed [u] 16 ) } )
    {
        : ( WGuard Page ) w ( rw_write [Page] l )
        ( slice_put [u] ( slice_from_vec [u] . ( wguard_get [Page] w ) data ) 0 1 )
    }
    : ( RGuard Page ) r ( rw_read [Page] l )
    : ( Slice u ) s ( bytes_of r )
    ( slice_put [u] s 3 7 )
    // The same write in other spellings: an inline view, a container
    // mutator on the lent Vec, and a helper that changes its argument.
    ( slice_put [u] ( slice_from_vec [u] . ( rguard_get [Page] r ) data ) 0 1 )
    : Page p ( rguard_get [Page] r )
    ( vec_push [u] . p data 9 )
    ( zero_first . p data )
    ^ 0
}
