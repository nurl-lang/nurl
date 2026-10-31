// signal_handler_over_a_stack_binding: as h503, `signal_install`: the runtime keeps the handler past
// the installing call, and one over a `: ~` local wrote a dead frame.
// Closed: signal_install keeps what it is handed, as h503.
// v0.80.0: accepted; AddressSanitizer reported stack-use-after-scope.
// map: §2.11 | A2 | rejected | h504 | as h503, `signal_install`: the runtime keeps the handler past the installing call, and one over a `: ~` local wrote a dead frame.
$ `stdlib/std/signal.nu`

: Counter { i n i max }

@ install → v {
    : ~ Counter c @ Counter { 0 10 }
    : i _r ( signal_install 10 \ i s → v { = . c n + . c n 1 } )
}

@ main → i {
    ( install )
    : i _x ( signal_raise 10 )
    ( signal_dispatch )
    ^ 0
}
