// A binding of an outer block given a field that cannot be copied out of
// a struct an inner block declares: the inner block drops the struct,
// fields and all, and the binding would go on borrowing the field (h328).
// A handle field would move out; this one cannot (a `% Drop` value leaves
// nothing in its place).
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

@ main → i {
    : Plain keep @ Plain { @ Conn { 1 } 0 }
    : ~ Conn a . keep c
    ? T {
        : Plain p @ Plain { @ Conn { 2 } 0 }
        = a . p c
    } {}
    ^ . a fd
}
