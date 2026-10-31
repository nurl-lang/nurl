// returned_closure_never_run_leaked_its_capture: a closure handed back by a function — `^ \ → v { ( eat r ) }`, `r` a `% Drop` value with no clone — took its capture over when it was made and released it only if run; never run, the value leaked. One that only read such a capture could not be handed back at all (h224).
// Closed: a returned closure's env owns such a capture under a flag of its own: the body clears it where it moves the value out, the env's drop releases what was not taken. Run again after the move it stops (its caller cannot see the move); copied, it stops (two owners of one value).
// this PR before the fix: LSan detected memory leaks.
// map: §7.5 | A2 | runs-clean | h239 | returned closure owning %Drop capture never run: capture leaks
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
}

@ mk → ( @ v ) {
    : Res r @ Res { ( vec_new [i] ) }
    ^ \ → v { ( eat r ) }
}

@ main → i {
    : ( @ v ) f ( mk )
    ^ 0
}
