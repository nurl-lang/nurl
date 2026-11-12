// Two generic structs declared below the function that names them, one a
// field of the other: the instance of the outer one is made where it is
// named, with the inner one's fields — `( Outer i )` reaches the `Rc` in
// `( Inner i )` and may not be captured by a thread's closure (agora #716).
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Outer i ) h @ ( Outer i ) { @ ( Inner i ) { ( rc_clone [i] mine ) } }
    ?? ( thread_spawn \ → v { : ( Outer i ) taken h } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}

: Outer [T] { ( Inner T ) inner }

: Inner [T] { ( Rc T ) held }
