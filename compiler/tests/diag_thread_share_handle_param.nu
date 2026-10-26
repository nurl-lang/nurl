// diag_thread_share_handle_param.nu
// A thread's closure may not capture a parameter of a share handle that
// is not asserted `% Sync`: the caller keeps the PNCounter it passed and
// would change it under the thread. `sink` hands it over (h337).

$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ count_in_background PNCounter c → !Thread ThreadErr {
    ^ ( thread_spawn \ → v { ( pncounter_inc c 1 1 ) } )
}

@ main → i {
    : PNCounter a ( pncounter_new )
    : !Thread ThreadErr t ( count_in_background a )
    ( pncounter_inc a 2 1 )
    ?? t { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
