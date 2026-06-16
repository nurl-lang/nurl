// Borrow checker — transitive interprocedural escape (docs/MEMORY.md
// §2.7). `detach` escapes its param via thread_spawn. `forward` merely
// passes its own param straight to `detach`'s escaping slot — so the
// summary propagates: `forward` is inferred escaping too (it is
// compiled after `detach`, so g_fn_escapes[detach] is already known).
// Passing a stack-reference closure to `forward` is then flagged at
// the `( forward f )` call, two hops from the actual thread_spawn.
$ `stdlib/std/thread.nu`

: Counter { i n i max }

@ detach ( @ v ) cb → v {
    : !Thread ThreadErr t ( thread_spawn cb )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
}

@ forward ( @ v ) cb → v {
    ( detach cb )
}

@ leaky2 → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ( forward f )
}

@ main → i {
    ( leaky2 )
    ^ 0
}
