// OPEN in 0.72.0 — mem_forget inside a closure a thread runs, in a safe function: the forgotten String leaks.
// The closure given to thread_spawn builds a String and forgets it; a closure body in a safe function is
// safe code too. mem_forget is `unsafe`-only (§3.3d), but no check rejects it in 0.72.0
// (mem_forget_owned_vec); this is the spawned-closure context a fix must cover too.
// LSan: detected memory leaks — the String (24-byte control block from string_from, and its buffer).
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : !Thread ThreadErr r ( thread_spawn \ → v { : String s ( string_from `abc` ) ( mem_forget s ) } )
    ?? r { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_println `ran` )
    ^ 0
}
