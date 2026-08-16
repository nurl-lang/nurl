// Borrow checker — interprocedural escape through a PURE FORWARD CHAIN
// (docs/MEMORY.md §2.7). `leaky` hands a stack-reference closure to
// `outer`, which is defined below it and escapes the parameter only by
// handing it to `detach`, defined below THAT. When `outer` compiled,
// `detach` was still unknown, so `outer`'s own escape summary was
// empty — and the parked call-site check for `( outer f )` replayed
// against that empty summary and found nothing. The same three
// functions written bottom-up were rejected, which made definition
// order decide whether a dangling closure was a compile error.
//
// The propagation step is now parked as an implication and run to a
// fixed point (resolve_pending_impls) before any parked check replays,
// so the chain resolves from the deepest link outward.
$ `stdlib/std/thread.nu`

: Counter { i n i max }

@ leaky → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ( outer f )
}

@ outer ( @ v ) cb → v {
    ( detach cb )
}

@ detach ( @ v ) cb → v {
    : !Thread ThreadErr t ( thread_spawn cb )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
}

@ main → i {
    ( leaky )
    ^ 0
}
