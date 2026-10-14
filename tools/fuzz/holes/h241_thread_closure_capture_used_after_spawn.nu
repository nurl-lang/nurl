// H241: a closure literal handed to `thread_spawn` moved out a capture it cannot copy; the spawning frame could still use the value, so both released it.
// Closed: the closure takes the capture over when it is made: a later use in the frame is a use of a moved value.
// main's compiler: heap-use-after-free.
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
    : !Thread ThreadErr t ( thread_spawn \ → v { ( eat r ) } )
    ( eat r )
    ?? t { T th → ( thread_join th ) F e → {} }
    ^ 0
}
