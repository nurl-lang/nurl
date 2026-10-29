// H597: agora #154 — a closure that captured by reference, handed back through a callee (byref_closure_returned_through_an_unwrapping_callee).
// Closed: a payload carries its scrutinee's parameters, a closure part carries its referent (agora #154).
// v0.80.0: accepted; AddressSanitizer reported a fault.
@ unwrap ? ( @ i ) o → ( @ i ) { ^ ?? o { T g → g F → \ → i { ^ 0 } } }

@ mk → ( @ i ) {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    ^ ( unwrap @ ?( @ i ) { T f } )
}

@ main → i {
    : ( @ i ) g ( mk )
    ( nurl_println_int ( g ) )
    ^ 0
}
