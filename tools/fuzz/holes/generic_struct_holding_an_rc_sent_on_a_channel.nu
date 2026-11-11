// generic_struct_holding_an_rc_sent_on_a_channel: a `( Wrap i )` of `: Wrap [T] { ( Rc T ) held }` is sent on a `( Channel ( Wrap i ) )` while the sender keeps a share of the same `Rc`; the receiving thread and the sender clone and drop shares of the one count at once.
// main: accepted — `chan_send` asks whether the element type is Send, and the walk found no fields under the generic's bare name (ASan: heap-use-after-free).
// map: §6.5 | A3 | rejected | - | `( Wrap i )` of `: Wrap [T] { ( Rc T ) held }` sent on a Channel while the sender keeps a share: a generic struct is walked through the fields its instance has (agora #675)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Wrap [T] { ( Rc T ) held }

@ own ( Rc i ) r i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] r ) ) = j + j 1 }
        = k + k 1
    }
}

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Channel ( Wrap i ) ) ch ( chan_new [( Wrap i )] )
    : b sent ( chan_send [( Wrap i )] ch @ ( Wrap i ) { ( rc_clone [i] mine ) } )
    ?? ( thread_spawn \ → v {
        ?? ( chan_recv [( Wrap i )] ch ) {
            T w → { ( own . w held 20000 ) }
            F → {}
        }
    } ) {
        T t → { ( own mine 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] mine ) 1
}
