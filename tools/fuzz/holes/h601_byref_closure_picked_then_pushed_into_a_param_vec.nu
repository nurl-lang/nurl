// H601: agora #154 — a closure that captured by reference, handed back through a callee (byref_closure_picked_then_pushed_into_a_param_vec).
// Closed: a payload carries its scrutinee's parameters, a closure part carries its referent (agora #154).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/vec.nu`

: H { ( @ i ) cb i pad }

@ pick H h → ( @ i ) { ^ . h cb }

@ fill inout ( Vec ( @ i ) ) out → v {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    ( vec_push [( @ i )] out ( pick @ H { f 0 } ) )
}

@ main → i {
    : ~ ( Vec ( @ i ) ) out ( vec_new [( @ i )] )
    ( fill out )
    : ( @ i ) g ( vec_at [( @ i )] out 0 )
    ( nurl_println_int ( g ) )
    ^ 0
}
