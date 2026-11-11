// An Arc's payload must be Send and Sync, and a generic struct instance is
// asked through the fields the instance has: `( Arc ( Wrap i ) )` reaches an
// `Rc` and may not cross to another thread (agora #675).
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: Wrap [T] { ( Rc T ) held }

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Arc ( Wrap i ) ) a ( arc_new [( Wrap i )] @ ( Wrap i ) { ( rc_clone [i] mine ) } )
    ?? ( thread_spawn \ → v { : i n ( rc_strong [i] . ( arc_get [( Wrap i )] a ) held ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
