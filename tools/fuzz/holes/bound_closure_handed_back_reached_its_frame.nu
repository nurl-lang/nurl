// bound_closure_handed_back_reached_its_frame: a closure bound to a name (`: f \ → v { ( eat r ) }`) and then returned (`^ f`), or handed to a callee that keeps it, released a capture the frame released too (main), or reached the frame's drop flag after the frame returned (this PR's h236).
// Closed: a bound closure keeps its captures' drop flags in the frame only when the rest of the function only calls it; one named any other way owns them in its env.
// main's compiler: heap-use-after-free; this PR before the fix: stack-use-after-return.
// map: §7.5 | A2 | runs-clean | h243 | bound closure returned, its capture drop flag left in dead frame
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
}

@ mk → ( @ v ) {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( eat r ) ( puts `ran` ) }
    ^ f
}

@ main → i {
    : ( @ v ) g ( mk )
    ( g )
    ^ 0
}
