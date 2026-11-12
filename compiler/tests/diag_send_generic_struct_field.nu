// A generic struct is Send when the fields its INSTANCE has are: `( Wrap i )`
// holds an `( Rc i )`, so it may not be captured by a thread's closure. The
// instance's fields are registered under its own name (`Wrap__i64`), not the
// generic's (agora #675).
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

: Wrap [T] { ( Rc T ) held }

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Wrap i ) w @ ( Wrap i ) { ( rc_clone [i] mine ) }
    ?? ( thread_spawn \ → v { : i n ( rc_strong [i] . w held ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
