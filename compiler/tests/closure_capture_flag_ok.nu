// A closure that may move out a capture it cannot copy carries the
// binding's drop flag (h236): never run, or run without reaching the move,
// the frame drops the value; run to the move, the body takes it. Each
// `Res` prints `drop` once.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

: Box2 { ( @ v ) run }

@ eat sink Res r → v {
    ( nurl_println `eaten` )
}

@ never_run → v {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( eat r ) }
}

@ never_run_stored → v {
    : Res r @ Res { ( vec_new [i] ) }
    : Box2 b @ Box2 { \ → v { ( eat r ) } }
}

@ run_not_taken i k → v {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ? == k 1 { ( eat r ) } {} }
    ( f )
}

@ main → i {
    ( never_run )
    ( never_run_stored )
    ( run_not_taken 0 )
    ( run_not_taken 1 )
    ^ 0
}
