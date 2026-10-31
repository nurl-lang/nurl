// dyn_object_carries_a_kept_share_to_a_thread: a trait object of a `: Send` trait boxing a struct with a PNCounter crossed to a thread while the spawner kept a share of the counter: the crossing check walked fields, payloads, containers and closures, and a `%Bump` is `{ i8*, i8* }` with nothing it could see, so both threads changed one counter in place with no lock.
// Closed: a trait object's vtable carries the crossing check of the type it boxes (its last slot, filled for an impl of a `: Send` trait whose type reaches a handle whose copies are one state), and the check of a `%Trait` runs it; the crossing panics naming the handle (memory-safe).
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
// map: §6.5 | B | runs-clean | h360 | a trait object of a : Send trait boxing a PNCounter crossed to a thread while the spawner kept a share: the crossing check saw { i8*, i8* }; the vtable's last slot carries the boxed type's check, and the crossing panics
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

: Holder { PNCounter c }

% Bump [T] : Send { @ bump T self i n → i }

% Bump Holder {
    @ bump Holder h i n → i {
        : ~ i k 0
        ~ < k n { ( pncounter_inc . h c k 1 ) = k + k 1 }
        ^ 0
    }
}

@ main → i {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : %Bump d ( dyn Bump @ Holder { a } )
    ?? ( thread_spawn \ → v { : i _r ( bump d 20000 ) } ) {
        T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc b + k 100000 1 ) = k + k 1 } ( thread_join t ) }
        F _ → {}
    }
    ^ % ( pncounter_value b ) 256
}
