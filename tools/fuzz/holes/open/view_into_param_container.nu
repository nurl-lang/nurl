// OPEN in 0.72.0 — a view of a local string pushed into a container the caller holds: the caller reads freed memory.
// `add` pushes `x`, a fresh string it owns, into the caller's ( Vec s ) — which holds views — and releases
// `x` when it returns; main then reads element 0 through the Vec.
// ASan: heap-use-after-free in fputs <- nurl_println (main), reading element 0.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ add ( Vec s ) v → v {
    : s x ( nurl_str_cat `ab` `cde` )
    ( vec_push [s] v x )
}

@ main → i {
    : ( Vec s ) v ( vec_new [s] )
    ( add v )
    ?? ( vec_get [s] v 0 ) { T e → ( nurl_println e ) F → {} }
    ^ 0
}
