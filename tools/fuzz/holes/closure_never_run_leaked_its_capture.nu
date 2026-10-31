// closure_never_run_leaked_its_capture: a closure whose body moves out a capture that cannot be copied (a `% Drop` value with no clone) took the capture over when it was made, so a closure that was never run — or that ran without reaching the move — left the value with no owner: leaked. (Before h222 the frame kept it and released it a second time when the closure did run.)
// Closed: a closure that stays in its frame carries the binding's drop flag in its env; the body clears it only where it moves the value out, so the frame drops what the closure did not take.
// main (before this PR): heap-use-after-free when run; this PR before the fix: LSan detected memory leaks.
// map: §7.5 | A2 | runs-clean | h236 | closure that would move %Drop capture never runs: capture leaks
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
}

@ main → i {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( eat r ) }
    ^ 0
}
