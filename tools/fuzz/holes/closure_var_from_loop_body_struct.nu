// closure_var_from_loop_body_struct: agora #153 — a closure binding given a closure its owner lends (closure_var_from_loop_body_struct).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h516 | agora #153: closure_var_from_loop_body_struct
: Holder {
    ( @ i ) cb
    i pad
}

@ take_holder sink Holder h → v {}

@ main → i {
    : i x 42
    : ~ ( @ i ) f \ → i { ^ 0 }
    : ~ i k 0
    ~ < k 2 {
        : Holder h @ Holder { \ → i { ^ + x k } 0 }
        = f . h cb
        = k + k 1
    }
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
