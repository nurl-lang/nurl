// later_type_argument_that_is_only_send_after_an_arc_moved_into_a_thread_runs_clean: `: Two [A B] { A first B second }` — a `( Two ( Arc i ) Cell )` and a `( Two ( RwLocked i ) Cell )` are moved into a `thread_spawn` closure, which writes the Cell. An `Arc` and an `RwLocked` hold THEIR payload to Sync; the `Cell` beside them is the struct's own second field, in one thread at a time, and need only be Send.
// main: refused — it read a generic's arguments off the mangled name as one chain, so everything after an `Arc` or `RwLocked` first argument was held to Sync with its payload.
// The control for rc_as_a_later_type_argument_after_a_mutex_captured_by_a_thread.
// map: §6.5 | A3 | runs-clean | - | guard: `( Two ( Arc i ) Cell )` and `( Two ( RwLocked i ) Cell )` moved into a spawned closure: each type argument is asked the question its own place asks, and a sibling of an Arc is not the Arc's payload (agora #683)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/cell.nu`

: Two [A B] { A first B second }

@ main → i {
    : ( Two ( Arc i ) Cell ) p @ ( Two ( Arc i ) Cell ) { ( arc_new [i] 7 ) ( cell_new 8 ) }
    : ( Two ( RwLocked i ) Cell ) q @ ( Two ( RwLocked i ) Cell ) { ( rw_new [i] 9 ) ( cell_new 8 ) }
    : ( Channel i ) out ( chan_new [i] )
    ?? ( thread_spawn \ → v {
        ( cell_write_u8 . p second 0 ( arc_get [i] . p first ) )
        ( cell_write_u8 . q second 0 ( rw_get [i] . q first ) )
        : b told ( chan_send [i] out + ( cell_read_u8 . p second 0 ) ( cell_read_u8 . q second 0 ) )
    } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ?? ( chan_recv [i] out ) {
        T got → { ^ - got 16 }
        F → {}
    }
    ^ 9
}
