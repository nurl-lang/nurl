// A `% Sync` marker vouches for the container, never for what it holds: a
// Locked in an Arc hands its value to whichever thread locks it, so the
// value faces the Send question — an Rc, whose count is not atomic, is not
// Send (agora #121, h358).
$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`

@ main → i {
    : ( Arc ( Locked ( Rc i ) ) ) a ( arc_new [( Locked ( Rc i ) )] ( locked_new [( Rc i )] ( rc_new [i] 5 ) ) )
    : ( @ v ) body \ → v { : ( Rc i ) c ( locked_take [( Rc i )] ( arc_get [( Locked ( Rc i ) )] a ) ) ( locked_restore [( Rc i )] ( arc_get [( Locked ( Rc i ) )] a ) c ) }
    ?? ( thread_spawn body ) { T t → { ( thread_join t ) } F _ → {} }
    ^ 0
}
