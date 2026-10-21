// OPEN in 0.76.0 — two copies of one library handle over a counted block, one moved to a thread, changed on both.
// A library handle (docs/MEMORY.md §7.6) whose state lives in an rcbox is copied by sharing: a field read out of a struct (`: PNCounter mine . h c`) is another owner of the SAME state. A closure moves its captures, so the spawner cannot use `h` again — but `mine` is a second name of the state, and the Send derivation looks only at types: a struct of a `Shared` field and Vecs is Send. Both threads then change one counter in place with no lock: its replica Vec grows under the other thread.
// Unsound because the standard library's handles over unsynchronised state (crdt's PNCounter / OrSet, Cell, TcpConn, the net/ and dist/ tables — every `Shared` handle without a `% Send` / `% Sync` of its own, and the types that hold one) may cross a thread boundary while a copy stays. AddressSanitizer: heap-use-after-free or double-free in the replica Vec. Closing it is a rule for the derivation — a handle whose copies alias is Send only when it is asserted thread-safe (Rust's `Arc<T>: Send` needs `T: Sync`) — whose reach over the stdlib's handles is a design question; dist/heartbeat.nu (h318) and ext/mqtt.nu were changed not to rely on it. PkMemberTable and SymTab are marked by hand.
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

: Holder { PNCounter c }

@ main → i {
    : Holder h @ Holder { ( pncounter_new ) }
    : PNCounter mine . h c
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ( pncounter_inc . h c k 1 ) = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc mine + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value mine ) 256
}
