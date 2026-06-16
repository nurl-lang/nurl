// Borrow checker — return-escape composed with an escape sink
// (docs/MEMORY.md §2.8 + §2.3). `( id f )` propagates `f`'s stack
// reference out through the call result (id returns its parameter);
// that result is then handed straight to `thread_spawn`, which detaches
// it onto a worker thread that outlives `caller`. The reference dangles
// — flagged at the thread_spawn argument. Exercises §2.8 feeding a §2.3
// sink in one expression.
$ `stdlib/std/thread.nu`

: Counter { i n i max }

@ id ( @ v ) cb → ( @ v ) {
    ^ cb
}

@ caller → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    : !Thread ThreadErr t ( thread_spawn ( id f ) )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
}

@ main → i {
    ( caller )
    ^ 0
}
