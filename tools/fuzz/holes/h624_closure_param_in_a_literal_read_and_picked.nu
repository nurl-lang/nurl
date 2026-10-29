// H624: agora #173 — a closure binding stored into a literal field gets a copy of its env, which nothing dropped when the literal was a call's temporary (closure_param_in_a_literal_read_and_picked).
// Closed: the literal owns that copy and drops it with the rest (gen_agg_lit, __ao_cloid; agora #173).
// v0.80.0: accepted; LeakSanitizer reported the env copy (nurl_closure_own_copy).
: H { ( @ i ) cb i pad }

@ use H h → i { : ( @ i ) c . h cb ^ ( c ) }

@ wrap ( @ i ) f → i { ^ ( use @ H { f 0 } ) }

@ pick H h → ( @ i ) { ^ . h cb }

@ wrap2 ( @ i ) f → i { : ( @ i ) g ( pick @ H { f 0 } ) ^ ( g ) }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    ( nurl_println_int ( wrap f ) )
    ( nurl_println_int ( wrap2 f ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
