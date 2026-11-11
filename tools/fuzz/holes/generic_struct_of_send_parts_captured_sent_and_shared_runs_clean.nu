// generic_struct_of_send_parts_captured_sent_and_shared_runs_clean: generic structs whose fields are Send — `: Wrap [T] { ( Vec T ) v ( Arc T ) a ?T o }`, `: Two [A B] { A a B b }` — are captured by a `thread_spawn` closure, shared through an Arc and sent on a Channel, and used on the other thread.
// The control for the generic_struct_holding_an_rc_* probes.
// map: §6.5 | A3 | runs-clean | - | guard: generic structs of Send fields captured by a spawned closure, shared in an Arc and sent on a Channel: an instance is walked through its own fields, and Send ones pass (agora #675)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: Wrap [T] { ( Vec T ) v ( Arc T ) a ? T o }
: Two [A B] { A a B b }

@ main → i {
    : ( Wrap i ) w @ ( Wrap i ) { ( vec_new [i] ) ( arc_new [i] 7 ) @ ?i { T 3 } }
    ( vec_push [i] . w v 4 )
    : ( Two i ( Vec i ) ) p @ ( Two i ( Vec i ) ) { 2 ( vec_new [i] ) }
    : ( Arc ( Two i ( Wrap i ) ) ) shared ( arc_new [( Two i ( Wrap i ) )] @ ( Two i ( Wrap i ) ) { 1 @ ( Wrap i ) { ( vec_new [i] ) ( arc_new [i] 8 ) @ ?i { F } } } )
    : ( Arc ( Two i ( Wrap i ) ) ) theirs ( arc_clone [( Two i ( Wrap i ) )] shared )
    : ( Channel ( Wrap i ) ) ch ( chan_new [( Wrap i )] )
    : b sent ( chan_send [( Wrap i )] ch @ ( Wrap i ) { ( vec_new [i] ) ( arc_new [i] 9 ) @ ?i { F } } )
    : ~ i got 0
    ?? ( thread_spawn \ → v {
        ( vec_push [i] . w v ( arc_get [i] . w a ) )
        ( vec_push [i] . p b . p a )
        : i x . ( arc_get [( Two i ( Wrap i ) )] theirs ) a
        ?? ( chan_recv [( Wrap i )] ch ) { T m → { ( vec_push [i] . m v x ) } F → {} }
    } ) {
        T t → { = got ( thread_join t ) }
        F _ → {}
    }
    ^ - . ( arc_get [( Two i ( Wrap i ) )] shared ) a 1
}
