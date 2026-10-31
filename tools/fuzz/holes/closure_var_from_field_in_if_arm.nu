// closure_var_from_field_in_if_arm: agora #153 — a closure binding given a closure its owner lends (closure_var_from_field_in_if_arm).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h519 | agora #153: closure_var_from_field_in_if_arm
$ `stdlib/core/string.nu`

: Holder {
    ( @ i ) cb
    i pad
}

@ take_holder sink Holder h → v {}

@ main → i {
    : i x 42
    : b c == ( nurl_str_len `a` ) 1
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : Holder h @ Holder { \ → i { ^ x } 0 }
        ? c { = f . h cb } {}
    }
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
