// diag_closure_var_lent_reassigned.nu — a `~` closure binding that owned
// its closure, given one its owner lends (agora #153): a field of a
// struct, a `??` payload, a borrowed closure binding. It borrows from that
// owner from then on, so calling it after the owner ends is rejected.

: Holder {
    ( @ i ) cb
    i pad
}

@ take_holder sink Holder h → v {}

@ take_opt sink ? ( @ i ) o → v {}

@ from_a_field_in_a_block → i {
    : i x 42
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : Holder h @ Holder { \ → i { ^ x } 0 }
        = f . h cb
    }
    ^ ( f )
}

@ from_a_payload_then_sunk sink ? ( @ i ) o → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    ?? o {
        T cb → { = f cb }
        F → {}
    }
    ( take_opt o )
    ^ ( f )
}

@ from_a_borrowed_binding → i {
    : i x 42
    : ~ ( @ i ) f \ → i { ^ 0 }
    : Holder h @ Holder { \ → i { ^ x } 0 }
    : ( @ i ) g . h cb
    = f g
    ( take_holder h )
    ^ ( f )
}

@ main → i { ^ 0 }
