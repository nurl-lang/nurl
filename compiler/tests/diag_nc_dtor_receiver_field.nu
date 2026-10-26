// A destructor storing a field of the value it is dropping, where the
// field's type has a Drop of its own and no Clone: here a generic drop
// hook building a generic literal, the shape of std/pool.nu's checkout
// guard (Agora #73). Nothing empties the field and the receiver's drop
// glue releases it once the hook returns, so the literal's copy was
// released twice (h322). The field is lent, as a parameter's is.
// (diag_nc_dtor_receiver_field_vec / _store: a `% Drop` impl's container
// store, a hook's field store.)
: Conn {
    i fd
}

% Drop Conn {
    @ drop Conn c → v {}
}

: Slot [A] {
    A val
    i n
}

: Guard [A] {
    A val
    i k
}

@ Guard_drop [A] sink ( Guard A ) g → v {
    : ( Slot A ) s @ ( Slot A ) { . g val 1 }
}

@ main → i {
    : ( Guard Conn ) g @ ( Guard Conn ) { @ Conn { 1 } 0 }
    ^ 0
}
