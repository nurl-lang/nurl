// diag_send_closure_param.nu — a closure's captures are not in its type, so
// whether it may run on another thread is decided by following the value:
// `run_twice` spawns the closure it is handed, which makes its parameter a
// thread boundary, and the closure main builds captures an Rc (whose count
// is not atomic). The error is at the call that hands it over and names the
// capture and the line the closure was built on (docs/MEMORY.md §6.5).
$ `stdlib/std/rc.nu`
$ `stdlib/std/async.nu`

: Node { i v }

@ run_twice ( @ v ) f → v {
    : Fiber a ( spawn_joinable \ → v { ( f ) } )
    : Fiber b ( spawn_joinable \ → v { ( f ) } )
    ( fiber_join a ) ( fiber_join b )
}

@ main → i {
    : ( Rc Node ) r ( rc_new [Node] @ Node { 1 } )
    ( run_twice \ → v { ( nurl_print_int . ( rc_get [Node] r ) v ) } )
    ^ 0
}
