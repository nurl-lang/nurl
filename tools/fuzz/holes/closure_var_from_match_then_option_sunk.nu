// closure_var_from_match_then_option_sunk: agora #153 — a closure binding given a closure its owner lends (closure_var_from_match_then_option_sunk).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h515 | agora #153: closure_var_from_match_then_option_sunk
@ take_opt sink ? ( @ i ) o → v {}

@ main → i {
    : i x 42
    : ?( @ i ) o @ ?( @ i ) { T \ → i { ^ x } }
    : ~ ( @ i ) f \ → i { ^ 0 }
    ?? o {
        T cb → { = f cb }
        F → {}
    }
    ( take_opt o )
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
