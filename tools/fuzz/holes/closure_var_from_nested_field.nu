// closure_var_from_nested_field: agora #153 — a closure binding given a closure its owner lends (closure_var_from_nested_field).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h520 | agora #153: closure_var_from_nested_field
: Holder {
    ( @ i ) cb
    i pad
}

@ take_holder sink Holder h → v {}

: W { Holder h i pad }

@ main → i {
    : i x 42
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : W w @ W { @ Holder { \ → i { ^ x } 0 } 0 }
        = f . . w h cb
    }
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
