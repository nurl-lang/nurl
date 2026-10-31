// closure_var_from_borrowed_closure_var: agora #153 — a closure binding given a closure its owner lends (closure_var_from_borrowed_closure_var).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h518 | agora #153: closure_var_from_borrowed_closure_var
: Holder {
    ( @ i ) cb
    i pad
}

@ take_holder sink Holder h → v {}

@ main → i {
    : i x 42
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : Holder h @ Holder { \ → i { ^ x } 0 }
        : ( @ i ) g . h cb
        = f g
    }
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
