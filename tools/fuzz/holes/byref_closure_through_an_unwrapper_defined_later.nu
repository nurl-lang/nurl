// byref_closure_through_an_unwrapper_defined_later: agora #154 — a closure that captured by reference, handed back through a callee (byref_closure_through_an_unwrapper_defined_later).
// Closed: a payload carries its scrutinee's parameters, a closure part carries its referent (agora #154).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.8 | A2 | rejected | h600 | agora #154: byref_closure_through_an_unwrapper_defined_later
@ mk → ( @ i ) {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    ^ ( unwrap_later @ ?( @ i ) { T f } )
}

@ main → i {
    : ( @ i ) g ( mk )
    ( nurl_println_int ( g ) )
    ^ 0
}

@ unwrap_later ? ( @ i ) o → ( @ i ) { ^ ?? o { T g → g F → \ → i { ^ 0 } } }
