// A generic struct declared below the function that names its instance has
// its fields there all the same: `( Wrap i )` reaches an `Rc` and may not be
// captured by a thread's closure (agora #716).
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Wrap i ) h @ ( Wrap i ) { ( rc_clone [i] mine ) }
    ?? ( thread_spawn \ → v { : ( Wrap i ) taken h } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}

: Wrap [T] { ( Rc T ) held }
