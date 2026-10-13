// H229: a field that cannot be copied (a `% Drop` value with no clone) handed to a `sink` — `( eat . h r )` — went over while the struct kept it: the callee released it and the struct released it again when it was dropped. A String field is emptied where it lives; this one could not be.
// Closed: moving such a field out of a struct that still drops it is rejected — move the whole struct, or take the value out by replacing the field.
// main (before this PR): ASan heap-use-after-free.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ eat sink Res r → v {
}

@ main → i {
    : Hold h @ Hold { @ Res { ( vec_new [i] ) } 1 }
    ( eat . h r )
    ^ 0
}
