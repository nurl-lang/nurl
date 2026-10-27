// diag_arc_dyn_payload_frozen.nu — what arc_get lends of an `( Arc %Job )`
// is frozen like any payload (docs/MEMORY.md §6.5), and a trait object
// reaches its box: a method whose receiver is `inout` changes the box in
// place — the storage every thread holding a clone reads — whatever its
// impls write. Rejected called on the lend, on a struct field holding the
// object, and through a helper that hands its parameter on (the helper's
// summary is closed with the impls'). A read guard's view is frozen the
// same way.
$ `stdlib/std/arc.nu`
$ `stdlib/std/rwlock.nu`

: Count { i n }

% Job [T] : Send Sync { @ bump inout T self → v }

% Job Count { @ bump inout Count c → v { = . c n + . c n 1 } }

: Holder { % Job j }

@ poke inout %Job j → v { ( bump j ) }

@ main → i {
    : ( Arc % Job ) a ( arc_new [% Job] ( dyn Job @ Count { 7 } ) )
    : ~ % Job j ( arc_get [% Job] a )
    ( bump j )
    ( poke j )
    : ( Arc Holder ) h ( arc_new [Holder] @ Holder { ( dyn Job @ Count { 7 } ) } )
    : ~ Holder hv ( arc_get [Holder] h )
    ( bump . hv j )
    : ( RwLocked % Job ) l ( rw_new [% Job] ( dyn Job @ Count { 7 } ) )
    : ( RGuard % Job ) g ( rw_read [% Job] l )
    : ~ % Job k ( rguard_get [% Job] g )
    ( bump k )
    ^ 0
}
