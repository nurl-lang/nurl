// A closure that may leave the frame it is made in — handed to a thread,
// to a callee, bound and handed on — owns a capture it cannot copy under
// a flag of its own (h240): a copy takes it over, so the thread's copy
// releases it, and a closure bound for a thread but never handed over
// releases it with its env. One that only reads it may go to a thread, or
// be handed back inside a struct (h224 rejected that: the env now owns it).
// Each `Res` prints `drop` once.
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
    ( nurl_println `eaten` )
}

@ join ! Thread ThreadErr t → v {
    ?? t { T th → ( thread_join th ) F e → {} }
}

@ never_spawned b go → v {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( eat r ) }
    ? go { ( join ( thread_spawn f ) ) } {}
}

@ thread_reads → v {
    : Res r @ Res { ( vec_new [i] ) }
    ( vec_push [i] . r buf 3 )
    ( join ( thread_spawn \ → v { ( nurl_println_int ( vec_len [i] . r buf ) ) } ) )
}

@ twice ( @ v ) f → v { ( f ) ( f ) }

@ called_and_handed_on → v {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( nurl_println_int ( vec_len [i] . r buf ) ) }
    ( f )
    ( twice f )
}

@ bound_returned → ( @ v ) {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( eat r ) }
    ^ f
}

: Box2 { ( @ i ) get }

@ boxed_reader → Box2 {
    : Res r @ Res { ( vec_new [i] ) }
    ( vec_push [i] . r buf 5 )
    : ( @ i ) f \ → i { ( vec_len [i] . r buf ) }
    ^ @ Box2 { f }
}

@ main → i {
    ( never_spawned F )
    ( never_spawned T )
    ( thread_reads )
    ( called_and_handed_on )
    : ( @ v ) g ( bound_returned )
    ( g )
    : Box2 b ( boxed_reader )
    : ( @ i ) get . b get
    ( nurl_println_int ( get ) )
    ^ 0
}
