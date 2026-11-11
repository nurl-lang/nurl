// generic_struct_holding_an_rc_as_an_arc_payload_dropped_by_the_receiving_thread: an `( Arc ( Wrap i ) )` of `: Wrap [T] { ( Rc T ) held }` is sent on a Channel; the receiving thread drops each Arc — and with it a share of the sender's `Rc` — while the sender clones and drops shares of the same count.
// main: accepted — an Arc's payload must be Send and Sync, and the walk found no fields under the generic's bare name (ASan: double-free).
// map: §6.5 | A3 | rejected | - | `( Channel ( Arc ( Wrap i ) ) )` of `: Wrap [T] { ( Rc T ) held }` captured by a spawned closure that drops what it receives: a generic struct is walked through the fields its instance has (agora #675)
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Wrap [T] { ( Rc T ) held }

@ own ( Rc i ) r i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Rc i ) c ( rc_clone [i] r )
        = k + k 1
    }
}

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Channel ( Arc ( Wrap i ) ) ) ch ( chan_new [( Arc ( Wrap i ) )] )
    ?? ( thread_spawn \ → v {
        : ~ b more T
        ~ more {
            ?? ( chan_recv [( Arc ( Wrap i ) )] ch ) {
                T a → {}
                F → { = more F }
            }
        }
    } ) {
        T t → {
            : ~ i k 0
            ~ < k 20000 {
                : b sent ( chan_send [( Arc ( Wrap i ) )] ch ( arc_new [( Wrap i )] @ ( Wrap i ) { ( rc_clone [i] mine ) } ) )
                ( own mine 40 )
                = k + k 1
            }
            ( chan_close [( Arc ( Wrap i ) )] ch )
            ( thread_join t )
        }
        F _ → {}
    }
    ^ - ( rc_strong [i] mine ) 1
}
