// A borrowed value that cannot be copied — a parameter's field whose type
// has a Drop of its own and no Clone — handed to a callee that keeps it
// (vec_push's element). The Vec would own what the Holder still owns, and
// both would drop it: it was moved in silently and the second drop was a
// use-after-free. The owner has to give it up instead (a 'sink'
// parameter, or the owner itself).
$ `stdlib/core/vec.nu`

: Conn {
    i fd
}

% Drop Conn {
    @ drop Conn c → v {}
}

: Holder {
    Conn c
}

@ keep Holder h ( Vec Conn ) out → v {
    ( vec_push [Conn] out . h c )
}

@ main → i {
    ^ 0
}
