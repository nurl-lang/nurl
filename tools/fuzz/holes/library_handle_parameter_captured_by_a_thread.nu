// library_handle_parameter_captured_by_a_thread: a function handed a PNCounter started a thread whose closure captured that parameter; the caller kept changing the counter it passed while the thread changed the same state, with no lock.
// Closed: a thread's closure may not capture a parameter (not `sink`) of a share handle that is not asserted `% Sync`: its caller keeps the handle. Declare the parameter `sink` and the handle moves with the closure.
// v0.78.0: accepted; ASan reported heap-use-after-free / double-free in the replica Vec.
// map: §6.5 | A3 | rejected | h337 | a thread's closure captured a parameter of such a handle while its caller kept changing the one it passed: rejected unless the parameter is sink
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ run PNCounter c → Thread {
    ?? ( thread_spawn \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc c k 1 ) = k + k 1 } } ) {
        T t → { ^ t }
        F _ → { ( nurl_panic `spawn` ) }
    }
}

@ main → i {
    : PNCounter a ( pncounter_new )
    : Thread t ( run a )
    : ~ i k 0
    ~ < k 20000 { ( pncounter_inc a + k 100000 1 ) = k + k 1 }
    ( thread_join t )
    ^ 0
}
