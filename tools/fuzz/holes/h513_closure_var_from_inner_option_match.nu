// H513: agora #153 — a closure binding given a closure its owner lends (closure_var_from_inner_option_match).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : i x 42
        : ?( @ i ) o @ ?( @ i ) { T \ → i { ^ x } }
        ?? o {
            T cb → { = f cb }
            F → {}
        }
    }
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
