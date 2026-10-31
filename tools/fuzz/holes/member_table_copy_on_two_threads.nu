// member_table_copy_on_two_threads: two copies of one PkMemberTable (a struct field and a binding read out of it), one moved to a thread: both threads grew the member Vec in place, with no lock. dist/heartbeat.nu's thread held a table the same way, under a mutex the caller had to remember to take around its own changes.
// Closed: PkMemberTable is `% NotSend` (every copy is one table, changed in place); a thread that announces the node alive holds pktable_liveness — a copy of the self pubkey and the table's incarnation Atomic — and heartbeat_start takes no table and no mutex into its thread.
// v0.76.0: accepted; glibc aborted with "realloc(): invalid old size" (heap corruption).
// map: §6.5 | A3 | rejected | h319 | two copies of one PkMemberTable, one moved to a thread, both grew its member Vec (dist/heartbeat's shape); the table is % NotSend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/net/membership.nu`

@ pk_of i k → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u & k 255 ) ( vec_push [u] v # u & / k 256 255 ) ( vec_push [u] v # u / k 65536 )
    ^ v
}

: Holder { PkMemberTable t }

@ main → i {
    : ( Vec u ) me ( pk_of 999999 )
    : Holder h @ Holder { ( pktable_new me 1 2 3 4 ) }
    : PkMemberTable a . h t
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 3000 { : b _c ( pktable_apply . h t ( pk_of k ) 0 1 0 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T th → { : ~ i k 0 ~ < k 3000 { : b _c ( pktable_apply a ( pk_of + k 100000 ) 0 1 0 ) = k + k 1 } ( thread_join th ) } F _ → {} }
    ( nurl_println ( nurl_str_int ( pktable_count a ) ) )
    ^ 0
}
