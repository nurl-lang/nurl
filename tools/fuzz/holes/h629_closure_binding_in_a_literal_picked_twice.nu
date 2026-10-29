// H629: agora #173 — a closure binding stored into a literal field gets a copy of its env, which nothing dropped when the literal was a call's temporary (closure_binding_in_a_literal_picked_twice).
// Closed: the literal owns that copy and drops it with the rest (gen_agg_lit, __ao_cloid; agora #173).
// v0.80.0: accepted; LeakSanitizer reported the env copy (nurl_closure_own_copy).
: H { ( @ i ) cb i pad }

@ pick H h → ( @ i ) { ^ . h cb }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : ( @ i ) q ( pick @ H { f 0 } )
    ( nurl_println_int ( q ) )
    : ( @ i ) q2 ( pick @ H { f 1 } )
    ( nurl_println_int ( f ) )
    ^ 0
}
