// Borrow checker — interprocedural escape regression (docs/MEMORY.md
// §2.7). `detach` retains its closure parameter by handing it to
// thread_spawn, so the checker infers param 0 as *escaping* and
// publishes that in g_fn_escapes[detach]. The caller `leaky` builds a
// closure that captures a `: ~`-mutable Counter BY POINTER (a stack
// reference) and passes it to `detach` — the captured stack slot
// dangles the moment `leaky` returns. A per-function pass cannot see
// this; the function summary makes it an error at the call site.
$ `stdlib/std/thread.nu`

: Counter { i n i max }

@ detach ( @ v ) cb → v {
    : !Thread ThreadErr t ( thread_spawn cb )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
}

@ leaky → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ( detach f )
}

@ main → i {
    ( leaky )
    ^ 0
}
