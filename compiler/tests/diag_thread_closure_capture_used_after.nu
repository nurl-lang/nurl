// A closure handed to a thread takes over a capture it cannot copy (a
// `% Drop` value with no clone) when it is made (h240): the frame using
// it after that reads what the thread may already have released.
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
