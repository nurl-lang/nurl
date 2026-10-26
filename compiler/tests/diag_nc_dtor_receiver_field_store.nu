// A drop hook storing a field of its receiver into another struct's
// field, where the field's type has a Drop of its own and no Clone: the
// other struct and the receiver's drop glue would both release it (h322).
// The field is lent, as a parameter's is.
: Conn {
    i fd
}

% Drop Conn {
    @ drop Conn c → v {}
}

: Lease {
    Conn c
    i n
}

: Spare {
    Conn c
    i n
}

@ Lease_drop sink Lease l → v {
    : ~ Spare s @ Spare { @ Conn { 3 } 0 }
    = . s c . l c
}

@ main → i {
    : Lease l @ Lease { @ Conn { 1 } 0 }
    ^ 0
}
