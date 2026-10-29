// H627: agora #173 — a closure binding stored into a literal field gets a copy of its env, which nothing dropped when the literal was a call's temporary (closure_binding_in_a_result_literal_unwrapped).
// Closed: the literal owns that copy and drops it with the rest (gen_agg_lit, __ao_cloid; agora #173).
// v0.80.0: accepted; LeakSanitizer reported the env copy (nurl_closure_own_copy).
@ unwrap ! ( @ i ) i r → ( @ i ) { ^ ?? r { T g → g F e → \ → i { ^ 0 } } }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : ( @ i ) g ( unwrap @ !( @ i ) i { T f } )
    ( nurl_println_int ( g ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
