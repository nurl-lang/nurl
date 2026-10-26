// A field that cannot be copied — a `% Drop` value with no Clone — read
// out of a local struct and stored into a literal or another struct's
// field. The struct it was read out of still drops it, and a `% Drop`
// value has no empty state to leave behind, so the read is a lend: the
// store would need a copy, and there is none (h324, h326; h325 is the
// container store, h229 the `sink` argument).
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

@ into_literal → i {
    : Plain p @ Plain { @ Conn { 1 } 0 }
    : Box b @ Box { . p c 1 }
    ^ . b n
}

@ into_field → i {
    : Plain p @ Plain { @ Conn { 1 } 0 }
    : ~ Box b @ Box { @ Conn { 2 } 0 }
    = . b c . p c
    ^ . b n
}

@ main → i {
    ^ + ( into_literal ) ( into_field )
}
