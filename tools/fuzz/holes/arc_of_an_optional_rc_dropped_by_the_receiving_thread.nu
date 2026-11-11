// arc_of_an_optional_rc_dropped_by_the_receiving_thread: an `( Arc ?( Rc i ) )` is sent on a Channel; the receiving thread drops each Arc — and with it a share of the sender's `Rc` — while the sender clones and drops shares of the same count.
// main: accepted — the walk read the Arc's type argument with a peel that knows named types only, so the option `?( Rc i )` was skipped (ASan: heap-use-after-free).
// map: §6.5 | A3 | rejected | - | `( Channel ( Arc ?( Rc i ) ) )` captured by a spawned closure that drops what it receives: every type argument of a generic instance is walked as the type it is (agora #683)
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

@ own ( Rc i ) r i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Rc i ) c ( rc_clone [i] r )
        = k + k 1
    }
}

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Channel ( Arc ? ( Rc i ) ) ) ch ( chan_new [( Arc ? ( Rc i ) )] )
    ?? ( thread_spawn \ → v {
        : ~ b more T
        ~ more {
            ?? ( chan_recv [( Arc ? ( Rc i ) )] ch ) {
                T a → {}
                F → { = more F }
            }
        }
    } ) {
        T t → {
            : ~ i k 0
            ~ < k 20000 {
                : b sent ( chan_send [( Arc ? ( Rc i ) )] ch ( arc_new [? ( Rc i )] @ ?( Rc i ) { T ( rc_clone [i] mine ) } ) )
                ( own mine 40 )
                = k + k 1
            }
            ( chan_close [( Arc ? ( Rc i ) )] ch )
            ( thread_join t )
        }
        F _ → {}
    }
    ^ - ( rc_strong [i] mine ) 1
}
