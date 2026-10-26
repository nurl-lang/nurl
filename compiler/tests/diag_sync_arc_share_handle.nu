// diag_sync_arc_share_handle.nu
// An Arc's payload must be Sync. A PNCounter's fields look harmless, but
// every copy `arc_get` hands out is a share of one counter, changed in
// place with no lock: under the Sync question a share handle not
// asserted `% Sync` is not Sync (h338).

$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/dist/crdt.nu`

@ main → i {
    : ( Arc PNCounter ) p ( arc_new [PNCounter] ( pncounter_new ) )
    : ( @ v ) work \ → v { ( pncounter_inc ( arc_get [PNCounter] p ) 1 1 ) }
    : !Thread ThreadErr r ( thread_spawn work )
    ^ 0
}
