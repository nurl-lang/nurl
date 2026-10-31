// closure_argument_capture_used_after_call: a closure literal built as a call's argument (`( run \ → v { ( eat r ) } )`) moved out its capture, and the frame used `r` afterwards: freed twice. The closure's own body reset the key (`__in_call_arg__`) that said it was used right where it was made, so the move was recorded as a maybe-alias of nothing.
// Closed: the key is read before the body; and the closure, which may leave the frame through the callee, takes the capture over when it is made.
// main's compiler: heap-use-after-free.
// map: §2.11 | A2 | rejected | h242 | closure arg moves %Drop capture; frame consumes it after call
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
}

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : Res r @ Res { ( vec_new [i] ) }
    ( run \ → v { ( eat r ) } )
    ( eat r )
    ^ 0
}
