// Borrow checker — a FIELD of a parameter reaching an escaping slot
// (docs/MEMORY.md §2.7). `detachs` detaches `. box cb` onto a thread,
// so it retains a pointer into whatever struct the caller passed as
// `box` — the parameter escapes exactly as a bare `cb` would. The
// summary only ever recorded bare-identifier arguments, so the field
// spelling said nothing and `( detachs s )`, handing over a Slot that
// holds a stack-reference closure, compiled clean.
$ `stdlib/std/thread.nu`

: Counter { i n i max }
: Slot { ( @ v ) cb }

@ detachs Slot box → v {
    : !Thread ThreadErr t ( thread_spawn . box cb )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
}

@ leaky → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    : Slot s @ Slot { f }
    ( detachs s )
}

@ main → i {
    ( leaky )
    ^ 0
}
