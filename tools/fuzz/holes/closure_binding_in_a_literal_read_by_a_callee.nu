// closure_binding_in_a_literal_read_by_a_callee: agora #173 — a closure binding stored into a literal field gets a copy of its env, which nothing dropped when the literal was a call's temporary (closure_binding_in_a_literal_read_by_a_callee).
// Closed: the literal owns that copy and drops it with the rest (gen_agg_lit, __ao_cloid; agora #173).
// v0.80.0: accepted; LeakSanitizer reported the env copy (nurl_closure_own_copy).
// map: §7.5 | A2 | runs-clean | h623 | agora #173: closure binding in a literal read by a callee: env copy leaks
: H { ( @ i ) cb i pad }

@ use H h → i { : ( @ i ) c . h cb ^ ( c ) }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    ( nurl_println_int ( use @ H { f 0 } ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
