// sync_asserted_value_with_an_rc_in_an_rwlocked_in_an_arc_with_a_thread: `: S { ( Rc i ) r }` asserted `unsafe % Sync S { }` is the value of an `( RwLocked S )` shared in an `Arc` with a `thread_spawn` closure, while the spawner keeps another share of the `Rc`. Several readers reach an RwLocked's value at once and the last share's thread drops it, so the value must be Send as well as Sync; the marker answers Sync only.
// main: accepted — an RwLocked's value was asked Sync alone, which a `% Sync` marker answers without reading the `Rc` field.
// map: §6.5 | A3 | rejected | - | a `% Sync`-asserted value holding an `Rc`, in an `RwLocked` in an `Arc` captured by a spawned closure: an RwLocked's value is asked Send as well as Sync (agora #746)
$ `stdlib/std/arc.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/option.nu`

: S { ( Rc i ) r }

unsafe % Sync S {}

@ main → i {
    : ( Rc i ) keep ( rc_new [i] 1 )
    : ( Arc ( RwLocked S ) ) a ( arc_new [( RwLocked S )] ( rw_new [S] @ S { ( rc_clone [i] keep ) } ) )
    : ( Arc ( RwLocked S ) ) b ( arc_clone [( RwLocked S )] a )
    ?? ( thread_spawn \ → v { : ( Arc ( RwLocked S ) ) m b } ) {
        T t → {
            : ~ i j 0
            ~ < j 20000 { : ( Rc i ) d ( rc_clone [i] keep ) = j + j 1 }
            ( thread_join t )
        }
        F _ → {}
    }
    ^ - ( rc_get [i] keep ) 1
}
