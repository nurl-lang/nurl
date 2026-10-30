// rc_in_a_locked_in_an_arc_on_two_threads: an Rc in a Locked in an Arc (`( Arc ( Locked ( Rc i ) ) )`) crossed to a thread while the spawner kept a clone of the Rc: the Locked's `% Sync` marker stopped the Send/Sync walk, so nothing asked whether its value may move to another thread, and two threads changed the Rc's count with no atomic.
// Closed: a marker vouches for a container made to be shared, never for what it holds: a Locked's, a Channel's or a Pool's value faces the Send question and an RwLocked's the Sync question wherever the container is reached from several threads (an Arc's payload, a closure several threads run).
// v0.78.0: accepted; ASan reported heap-use-after-free (the count lost updates and reached zero early) or LSan a leak.
// map: §6.5 | A3 | rejected | h358 | an Rc in a Locked in an Arc crossed to a thread: a Sync marker vouches for the container, never for its value, which faces the Send question
$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Rc i ) r2 ( rc_clone [i] r )
    : ( Arc ( Locked ( Rc i ) ) ) a ( arc_new [( Locked ( Rc i ) )] ( locked_new [( Rc i )] r ) )
    : ( @ v ) body \ → v {
        : ( Rc i ) c ( locked_take [( Rc i )] ( arc_get [( Locked ( Rc i ) )] a ) )
        : ( Vec ( Rc i ) ) keep ( vec_new [( Rc i )] )
        : ~ i k 0
        ~ < k 200000 { ( vec_push [( Rc i )] keep ( rc_clone [i] c ) ) = k + k 1 }
        ( locked_restore [( Rc i )] ( arc_get [( Locked ( Rc i ) )] a ) c )
    }
    : ( Vec ( Rc i ) ) mine ( vec_new [( Rc i )] )
    ?? ( thread_spawn body ) {
        T t → {
            : ~ i k 0
            ~ < k 200000 { ( vec_push [( Rc i )] mine ( rc_clone [i] r2 ) ) = k + k 1 }
            ( thread_join t )
        }
        F _ → {}
    }
    ^ ( rc_get [i] r2 )
}
