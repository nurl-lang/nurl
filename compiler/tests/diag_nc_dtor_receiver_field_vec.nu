// A `% Drop` impl handing a field of its receiver to a callee that keeps
// it (vec_push's element), where the field's type has a Drop of its own
// and no Clone: the Vec and the receiver's drop glue would both release
// it (h322). The field is lent, as a parameter's is.
$ `stdlib/core/vec.nu`

: Conn {
    i fd
}

% Drop Conn {
    @ drop Conn c → v {}
}

: Holder {
    Conn c
    i n
}

% Drop Holder {
    @ drop sink Holder h → v {
        : ~ ( Vec Conn ) out ( vec_new [Conn] )
        ( vec_push [Conn] out . h c )
    }
}

@ main → i {
    : Holder h @ Holder { @ Conn { 1 } 0 }
    ^ 0
}
