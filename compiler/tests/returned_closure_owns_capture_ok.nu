// A returned closure owns a capture it cannot copy under a flag of its own
// (h239): never run, its env releases it; run, the body takes it; one
// that only reads it may be handed back and run again. Each `Res` prints
// `drop` once.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
    ( nurl_println `eaten` )
}

@ consumer → ( @ v ) {
    : Res r @ Res { ( vec_new [i] ) }
    ^ \ → v { ( eat r ) }
}

@ reader → ( @ i ) {
    : Res r @ Res { ( vec_new [i] ) }
    ( vec_push [i] . r buf 7 )
    ^ \ → i { ( vec_len [i] . r buf ) }
}

@ never_run → v {
    : ( @ v ) f ( consumer )
}

@ run_once → v {
    : ( @ v ) f ( consumer )
    ( f )
}

@ read_twice → v {
    : ( @ i ) g ( reader )
    ( nurl_println_int + ( g ) ( g ) )
}

@ main → i {
    ( never_run )
    ( run_once )
    ( read_twice )
    ^ 0
}
