// closure_bound_for_a_thread_never_handed_over_leaked: a closure bound to a name the function hands to a thread only on some path — `: f \ → v { ( eat r ) }`, `r` a `% Drop` value with no clone — took `r` over when it was made (h222); on the path that never spawned it, nothing released `r`.
// Closed: a closure that may leave its frame owns such a capture under a flag of its own (h239): its env releases what it was not run to take, and the copy a thread runs takes it over (the env it was copied from gives it up).
// this PR before the fix (h222): LSan detected memory leaks.
// map: §7.5 | A2 | runs-clean | h240 | closure for thread on untaken path took %Drop capture: leak
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
}

@ main → i {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( eat r ) }
    ? == 1 2 { : !Thread ThreadErr t ( thread_spawn f ) } {}
    ^ 0
}
