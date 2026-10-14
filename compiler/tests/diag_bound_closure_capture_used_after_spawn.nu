// A closure bound to a name and then handed to a thread owns a capture
// it cannot copy from the moment it is made (h240): the frame no longer
// does.
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
    : !Thread ThreadErr t ( thread_spawn f )
    ( eat r )
    ?? t { T th → ( thread_join th ) F e → {} }
    ^ 0
}
