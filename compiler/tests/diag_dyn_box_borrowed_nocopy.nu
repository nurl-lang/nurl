// `( dyn Trait v )` over a BORROWED value whose type owns a resource and
// has no copy — a parameter's field with a Drop of its own and no Clone.
// The box would free what the parameter still holds; a copyable value is
// copied into the box instead, and this one cannot be.
$ `stdlib/core/string.nu`

: Conn {
    i fd
}

% Drop Conn {
    @ drop Conn c → v {}
}

% Named [T] {
    @ id T self → i
}

% Named Conn { @ id Conn c → i { ^ . c fd } }

: Holder {
    Conn c
}

@ boxed Holder h → %Named { ^ ( dyn Named . h c ) }

@ main → i {
    ^ 0
}
