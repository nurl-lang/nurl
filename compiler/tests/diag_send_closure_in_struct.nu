// diag_send_closure_in_struct.nu — a closure inside a struct crosses a
// thread boundary with it: here the struct is queued on a channel, whose
// receiver may be any thread or fiber. The closure captures an Rc, so the
// send is rejected at the chan_send, naming the capture and where the
// closure was built — not wherever the struct type is declared.
$ `stdlib/std/rc.nu`
$ `stdlib/std/channel.nu`

: Node { i v }

: Job { ( @ v ) run }

@ main → i {
    : ( Rc Node ) r ( rc_new [Node] @ Node { 1 } )
    : ( Channel Job ) ch ( chan_new [Job] )
    : ( @ v ) f \ → v { ( nurl_print_int . ( rc_get [Node] r ) v ) }
    ( chan_send [Job] ch @ Job { f } )
    ^ 0
}
