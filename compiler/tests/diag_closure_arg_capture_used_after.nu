// A closure built as a call's argument that moves out a capture it
// cannot copy took it over (h240): the callee ran it, and the frame then
// used a value already released. (The closure's body reset the key that
// told the two apart, so this compiled and freed it twice.)
$ `stdlib/core/vec.nu`

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
