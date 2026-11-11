// Every type argument of a generic instance is asked as the type it is: an
// option of an `Rc` inside a Vec is no more Send than the `Rc` (agora #683 —
// `( Vec ( Rc i ) )` and a bare `?( Rc i )` were refused, `( Vec ?( Rc i ) )`
// was not).
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Vec ? ( Rc i ) ) xs ( vec_new [? ( Rc i )] )
    ( vec_push [? ( Rc i )] xs @ ?( Rc i ) { T ( rc_clone [i] mine ) } )
    ?? ( thread_spawn \ → v { : i n ( vec_len [? ( Rc i )] xs ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
