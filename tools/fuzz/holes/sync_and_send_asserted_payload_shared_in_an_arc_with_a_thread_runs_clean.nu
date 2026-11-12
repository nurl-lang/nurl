// sync_and_send_asserted_payload_shared_in_an_arc_with_a_thread_runs_clean: `: S { i n ( Arc i ) m }` asserted `unsafe % Sync S { }` — a payload that is Send by its fields — is shared in an `( Arc S )` with a `thread_spawn` closure, and both threads read it. Asking an Arc's payload Send as well as Sync refuses no payload that is both.
// The control for sync_asserted_payload_with_an_rc_shared_in_an_arc_with_a_thread.
// map: §6.5 | A3 | runs-clean | - | guard: a `% Sync`-asserted payload whose fields are Send, in an `Arc` captured by a spawned closure, crosses (agora #746)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/option.nu`

: S { i n ( Arc i ) m }

unsafe % Sync S {}

@ main → i {
    : ( Arc S ) a ( arc_new [S] @ S { 4 ( arc_new [i] 5 ) } )
    : ( Arc S ) b ( arc_clone [S] a )
    : ( Channel i ) out ( chan_new [i] )
    ?? ( thread_spawn \ → v { : b told ( chan_send [i] out + . ( arc_get [S] b ) n ( arc_get [i] . ( arc_get [S] b ) m ) ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ?? ( chan_recv [i] out ) {
        T got → { ^ - got 9 }
        F → {}
    }
    ^ 9
}
