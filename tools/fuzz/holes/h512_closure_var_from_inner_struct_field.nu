// H512: agora #153 — a closure binding given a closure its owner lends (closure_var_from_inner_struct_field).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
: Holder {
    ( @ i ) cb
    i pad
}

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : i x 42
        : Holder h @ Holder { \ → i { ^ x } 0 }
        = f . h cb
    }
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
