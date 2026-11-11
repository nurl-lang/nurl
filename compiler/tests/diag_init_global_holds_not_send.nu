// diag_init_global_holds_not_send.nu — every thread reads a global set at
// start, so what it holds is shared between them: a Locked hands its value
// to one thread at a time, and that value must be Send, as it must where a
// Locked crosses to a thread. An Rc is not: two threads copying it out
// under the lock drop their copies outside it, on a count that is not
// atomic (agora #639).
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

@ make → ( Locked ( Rc i ) ) { ^ ( locked_new [( Rc i )] ( rc_new [i] 5 ) ) }

: ( Locked ( Rc i ) ) g_one ( make )

@ main → i {
    : ( Rc i ) mine ( locked_get [( Rc i )] g_one )
    ^ - ( rc_strong [i] mine ) 2
}
