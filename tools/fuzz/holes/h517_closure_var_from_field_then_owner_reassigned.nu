// H517: agora #153 — a closure binding given a closure its owner lends (closure_var_from_field_then_owner_reassigned).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
: Holder {
    ( @ i ) cb
    i pad
}

@ take_holder sink Holder h → v {}

@ main → i {
    : i x 42
    : ~ Holder h @ Holder { \ → i { ^ x } 0 }
    : ~ ( @ i ) f \ → i { ^ 0 }
    = f . h cb
    = h @ Holder { \ → i { ^ 1 } 0 }
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
