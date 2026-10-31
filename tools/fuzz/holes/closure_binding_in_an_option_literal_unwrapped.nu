// closure_binding_in_an_option_literal_unwrapped: agora #173 — a closure binding stored into a literal field gets a copy of its env, which nothing dropped when the literal was a call's temporary (closure_binding_in_an_option_literal_unwrapped).
// Closed: the literal owns that copy and drops it with the rest (gen_agg_lit, __ao_cloid; agora #173).
// v0.80.0: accepted; LeakSanitizer reported the env copy (nurl_closure_own_copy).
// map: §7.5 | A2 | runs-clean | h621 | agora #173: closure binding in an option literal unwrapped: env copy leaks
@ unwrap ? ( @ i ) o → ( @ i ) { ^ ?? o { T g → g F → \ → i { ^ 0 } } }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : ( @ i ) g ( unwrap @ ?( @ i ) { T f } )
    ( nurl_println_int ( g ) )
    ^ 0
}
