// A returned literal holding a field that cannot be copied, read out of a
// local struct: the local is dropped, fields and all, on the way out, so
// the literal would lend what the return released (h327) — as `^ . p c`
// would. A parameter's field is lent back and stays legal.
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

: Box {
    Conn c
    i n
}

@ lend_back Plain p → Box {
    ^ @ Box { . p c 1 }
}

@ mk → Box {
    : Plain p @ Plain { @ Conn { 1 } 0 }
    ^ @ Box { . p c 1 }
}

@ main → i {
    : Box b ( mk )
    ^ . b n
}
