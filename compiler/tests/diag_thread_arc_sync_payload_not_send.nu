// An Arc's payload must be Send as well as Sync (docs/MEMORY.md §6.5):
// every thread holding a share reaches it, and the one that lets go of the
// last share drops it there. `S` is asserted `% Sync`, which answers the
// Sync question without reading its fields — and its `Rc` field is not
// Send: the last `( Arc S )` released on the worker would decrement the
// Rc's count there while `keep` uses it here (agora #746).
$ `stdlib/std/arc.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/option.nu`

: S { ( Rc i ) r }

unsafe % Sync S {}

@ main → i {
    : ( Rc i ) keep ( rc_new [i] 1 )
    : ( Arc S ) a ( arc_new [S] @ S { ( rc_clone [i] keep ) } )
    : ( Arc S ) b ( arc_clone [S] a )
    ?? ( thread_spawn \ → v { : i z ( rc_get [i] . ( arc_get [S] b ) r ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ ( rc_get [i] keep )
}
