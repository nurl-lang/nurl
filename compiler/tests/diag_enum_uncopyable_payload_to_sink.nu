// An enum's payload is lent to the arm (h231): one that cannot be copied
// cannot be handed to a `sink` — the enum still drops it.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: | Shape { Has Res Bare }

@ eat sink Res r → v {
}

@ main → i {
    : Shape s @ Shape { Has @ Res { ( vec_new [i] ) } }
    ?? s { Has r → { ( eat r ) } Bare → {} }
    ^ 0
}
