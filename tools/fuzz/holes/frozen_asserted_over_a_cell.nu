// frozen_asserted_over_a_cell: may a safe module write `% Frozen` on a struct of its own that holds a Cell (interior mutability), share it in an RwLocked and write the Cell from two threads through read guards? (A question, task #21, not a hole found: settled by this probe.)
// Closed: `% Frozen` only adds checks — what a frozen value lends is read-only — so safe code may write it; it does not make the Cell Sync. A read guard is `% Frozen` itself (stdlib/std/rwlock.nu), and `cell_write_u8` changes what it is handed, so the write through either guard is rejected where it is made; an Arc of the struct is rejected the same way (its payload is frozen), and `% Sync` over the Cell needs `unsafe` (h318, docs/MEMORY.md §3).
// v0.76.0: rejected (the frozen-view check); kept so a change to how markers stop the walk cannot let it through.
// map: §6.5 | A3 | rejected | h317 | a program's own % Frozen over a Cell, in an RwLocked, written through read guards on two threads: % Frozen only adds checks (question #21, rejected already)
$ `stdlib/core/cell.nu`
$ `stdlib/core/marker.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/thread.nu`

: Counter { Cell c }

% Frozen Counter {}

@ bump ( RwLocked Counter ) l → v {
    : ~ i k 0
    ~ < k 100000 {
        : ( RGuard Counter ) g ( rw_read [Counter] l )
        : Cell cc . ( rguard_get [Counter] g ) c
        ( cell_write_u8 cc 0 + ( cell_read_u8 cc 0 ) 1 )
        = k + k 1
    }
}

@ main → i {
    : ( RwLocked Counter ) l ( rw_new [Counter] @ Counter { ( cell_zero 8 ) } )
    : ( RwLocked Counter ) m ( RwLocked_share [Counter] l )
    : ( @ v ) body \ → v { ( bump m ) }
    ?? ( thread_spawn body ) { T t → { ( bump l ) ( thread_join t ) } F _ → {} }
    ^ 0
}
