// Borrow checker — interprocedural escape across a FORWARD call
// (docs/MEMORY.md §3). `leaky` passes a stack-reference closure to
// `detach`, which is defined LATER in the file. At the call site
// detach's escape summary is not yet known, so the inline §2.7 check
// cannot fire; the check is parked and replayed by
// resolve_pending_escapes() once the whole module has compiled and
// g_fn_escapes[detach] = {0} is final. detach escapes its parameter
// directly (thread_spawn), so its summary is complete regardless of
// definition order, and the forward call is now flagged just like the
// define-before-call form.
$ `stdlib/std/thread.nu`

: Counter { i n i max }

@ leaky → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ( detach f )
}

@ detach ( @ v ) cb → v {
    : !Thread ThreadErr t ( thread_spawn cb )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
}

@ main → i {
    ( leaky )
    ^ 0
}
