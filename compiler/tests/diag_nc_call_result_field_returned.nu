// Handing back a field that cannot be copied, read out of a call's
// result: the result is lent by an owner of its own for the rest of the
// scope (h330), dropped on the way out with the field in it — as a
// local's would be.
: Conn {
    i fd
}

% Drop Conn {
    @ drop Conn c → v {}
}

: Plain {
    Conn c
    i n
}

@ mk → Plain {
    ^ @ Plain { @ Conn { 1 } 0 }
}

@ take → Conn {
    ^ . ( mk ) c
}

@ main → i {
    : Conn c ( take )
    ^ . c fd
}
