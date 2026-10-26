// OPEN in 0.78.0 — a share of a library handle made before the handle moves to a thread, kept by the spawner, both changed.
// A library handle (docs/MEMORY.md §7.6) whose state lives in an rcbox is copied by sharing. A thread's closure moves such a handle when it is not asserted `% Sync` (h336), a parameter of one may not be captured (h337), and a closure that carries one to another thread takes it along (h340). A share made before the move is another owner the checker does not connect to the moved one: `( PNCounter_share a )` here, and equally a literal that stores one (`@ Holder { . h c }` kept while `h` goes) or a callee that keeps one. Both threads then change one counter in place with no lock.
// Unsound because the moved handle and the spawner's share are one state: its replica Vec grows under the other thread. AddressSanitizer: heap-use-after-free or double-free in the replica Vec. Closing it needs the checker to know which owners alias — a share of a non-Sync handle as an alias row that a thread's move of either side ends — or the crossing to check at run time that the moved handle has no other owner (agora #121; docs/MEMORY.md §6.2).
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc a k 1 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc b + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value b ) 256
}
