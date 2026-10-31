// library_handle_field_read_taken_by_a_thread: a binding read out of a struct's library handle field (`: PNCounter x . h c`) captured by a thread's closure: the thread's copy of the env shared the counter while `h` — still usable — kept it, and both changed it with no lock.
// Closed: the thread takes `x` over, and with it the field and its struct (h348): reading `h` after the spawn is rejected.
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
// map: §6.5 | A3 | rejected | h356 | a binding read out of a library handle field captured by a thread while its struct stayed usable: the thread takes the field and its struct along
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

: Holder { PNCounter c }

@ main → i {
    : Holder h @ Holder { ( pncounter_new ) }
    : PNCounter x . h c
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc x k 1 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc . h c + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ 0
}
