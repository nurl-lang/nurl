// byref_closure_returned_through_a_field_picking_callee: agora #154 — a closure that captured by reference, handed back through a callee (byref_closure_returned_through_a_field_picking_callee).
// Closed: a payload carries its scrutinee's parameters, a closure part carries its referent (agora #154).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.8 | A2 | rejected | h598 | agora #154: byref_closure_returned_through_a_field_picking_callee
: H { ( @ i ) cb i pad }

@ pick H h → ( @ i ) { ^ . h cb }

@ mk → ( @ i ) {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    ^ ( pick @ H { f 0 } )
}

@ main → i {
    : ( @ i ) g ( mk )
    ( nurl_println_int ( g ) )
    ^ 0
}
