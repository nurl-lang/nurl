// sync_asserted_payload_with_an_rc_shared_in_an_arc_with_a_thread: `: S { ( Rc i ) r }` asserted `unsafe % Sync S { }` is shared in an `( Arc S )` with a `thread_spawn` closure while the spawner keeps another share of the `Rc`. The marker answers Sync; it does not make the `Rc` Send, and the thread that lets go of the last `Arc` drops `S` — and the `Rc` share in it — on its own side, racing the spawner's count.
// main: accepted — an Arc's payload was asked Sync alone, and the Sync walk stops at a `% Sync` marker without reading the fields that make a type Send.
// map: §6.5 | A3 | rejected | - | a `% Sync`-asserted payload holding an `Rc`, in an `Arc` captured by a spawned closure: an Arc's payload is asked Send as well as Sync (agora #746)
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
    ?? ( thread_spawn \ → v {
        : ~ i k 0
        ~ < k 20000 { : ( Rc i ) c ( rc_clone [i] . ( arc_get [S] b ) r ) = k + k 1 }
    } ) {
        T t → {
            : ~ i j 0
            ~ < j 20000 { : ( Rc i ) d ( rc_clone [i] keep ) = j + j 1 }
            ( thread_join t )
        }
        F _ → {}
    }
    ^ - ( rc_get [i] keep ) 1
}
