// library_handle_in_a_literal_kept_by_the_spawner: a library handle stored into a literal (`: Holder h2 @ Holder { . h c }` — a borrowed field stored into an owner is a share) stayed with the spawner while `h` went to a thread: two owners of one counter, on two threads, changed it with no lock.
// Closed: the thread_spawn crossing finds the counter's block with two owners and panics (mem_send_check, h349).
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
// map: §6.5 | B | runs-clean | h350 | a literal storing a borrowed handle field (a share) kept while the struct went to a thread: thread_spawn's crossing check panics on the second owner
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

: Holder { PNCounter c }

@ main → i {
    : Holder h @ Holder { ( pncounter_new ) }
    : Holder h2 @ Holder { . h c }
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc . h c k 1 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc . h2 c + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value . h2 c ) 256
}
