// diag_send_closure_field.nu — a closure read out of a struct field is no
// more than what the struct can hold: `go` spawns the handler of the server
// it is passed, so its callers' handlers are checked — one capturing an Rc
// is rejected at the call to `go`.
$ `stdlib/std/rc.nu`
$ `stdlib/std/async.nu`

: Node { i v }

: Srv { ( @ v ) h }

@ go Srv s → v {
    : ( @ v ) f . s h
    : Fiber a ( spawn_joinable f )
    ( fiber_join a )
}

@ main → i {
    : ( Rc Node ) r ( rc_new [Node] @ Node { 1 } )
    : Srv srv @ Srv { \ → v { ( nurl_print_int . ( rc_get [Node] r ) v ) } }
    ( go srv )
    ^ 0
}
