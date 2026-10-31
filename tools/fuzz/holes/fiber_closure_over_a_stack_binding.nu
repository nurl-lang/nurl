// fiber_closure_over_a_stack_binding: `( spawn \ → v { = . c n + . c n 1 } )` with `c` a `: ~` local
// of the spawning function: the closure reached `c` by pointer, and the
// fiber ran after the frame was gone. thread_spawn was refused the same
// program; the three `spawn*` entries were not on the list of calls that
// keep what they are handed.
// Closed: every call that detaches a closure (__thr_is_detach) is one.
// v0.80.0: accepted; AddressSanitizer reported stack-use-after-scope.
// map: §2.11 | A2 | rejected | h503 | `( spawn \ → v { = . c n + . c n 1 } )` with `c` a `: ~` local of the spawning function: the closure reached `c` by pointer, and the fiber ran after the frame was gone. thread_spawn was refused…
$ `stdlib/std/async.nu`

: Counter { i n i max }

@ start → v {
    : ~ Counter c @ Counter { 0 10 }
    : Fiber _f ( spawn \ → v { = . c n + . c n 1 } )
}

@ main → i {
    ( runtime_init 1 )
    ( start )
    ( runtime_run )
    ^ 0
}
