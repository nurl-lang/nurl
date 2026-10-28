// H521: agora #153 — a closure binding given a closure its owner lends (closure_var_from_vec_get_then_freed).
// Closed: an assignment of another class clears the binding's `nh_` mark (agora #153).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/vec.nu`

@ main → i {
    : i x 42
    : ~ ( @ i ) f \ → i { ^ 0 }
    : ( Vec ( @ i ) ) v ( vec_new [( @ i )] )
    ( vec_push [( @ i )] v \ → i { ^ x } )
    ?? ( vec_get [( @ i )] v 0 ) {
        T cb → { = f cb }
        F → {}
    }
    ( vec_free [( @ i )] v )
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
