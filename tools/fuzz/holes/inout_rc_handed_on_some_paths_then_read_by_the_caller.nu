// inout_rc_handed_on_some_paths_then_read_by_the_caller: the Rc twin of inout_vec_handed_on_some_paths_then_pushed_by_the_caller. The emptied slot is a null Rc, and the caller read it.
// Closed: as for the Vec. After the call the argument is moved on some paths.
// main's compiler: compiled with no `unsafe`; rc_get read through the null handle (SIGSEGV).
// map: §7.6 | A2 | rejected | h978 | inout Rc handed to a sink on some paths by the callee, then read by the caller
$ `stdlib/std/rc.nu`

@ eat sink ( Rc i ) r → i { ^ ( rc_get [i] r ) }

@ g3 inout ( Rc i ) p i c → i {
    ? == c 1 { ^ ( eat p ) } {}
    ^ 0
}

@ main → i {
    : ~ ( Rc i ) w ( rc_new [i] 5 )
    ( nurl_println_int ( g3 w 1 ) )
    ( nurl_println_int ( rc_get [i] w ) )
    ^ 0
}
