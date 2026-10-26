// OPEN in 0.78.0 — two copies of one library handle over a counted block, one taken by a thread, both changed.
// A library handle (docs/MEMORY.md §7.6) whose state lives in an rcbox is copied by sharing: a closure's capture of it is another owner of the SAME state. A closure that runs on another thread moves a String or a Vec it captures — the spawner may not name it again — but a handle whose copy is a share stays the spawner's too (gen_closure_expr: "the thread or fiber takes a share of its own"), and the Send derivation looks only at types: a struct of a `Shared` field and Vecs is Send. Both threads then change one counter in place with no lock: its replica Vec grows under the other thread. Other spellings of it: a parameter the closure captures (its caller keeps the handle), and a share stored before the move (`@ Holder { . h c }` kept while `h` goes).
// Unsound because the standard library's handles over unsynchronised state (crdt's PNCounter / OrSet, Cell, the net/ and dist/ tables — every `Shared` handle without a `% Sync` of its own) may be shared with a thread while a copy stays. AddressSanitizer: heap-use-after-free or double-free in the replica Vec. Closing it is a rule for share handles at a thread boundary — one that is not asserted `% Sync` moves as a Vec does, and a parameter or a stored copy of one may not cross — whose reach over the handles the standard library shares on purpose (a TcpListener every accepting worker holds, an HTTP or QUIC server) is a design question: each needs its state shown thread-safe and marked, or a different hand-over. The shape agora #66 was found with (a binding read out of a field) is closed: h333.
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc a k 1 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc a + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value a ) 256
}
