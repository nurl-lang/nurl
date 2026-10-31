// closure_binding_in_a_literal_through_a_generic: agora #173 — a closure binding stored into a literal field gets a copy of its env, which nothing dropped when the literal was a call's temporary (closure_binding_in_a_literal_through_a_generic).
// Closed: the literal owns that copy and drops it with the rest (gen_agg_lit, __ao_cloid; agora #173).
// v0.80.0: accepted; LeakSanitizer reported the env copy (nurl_closure_own_copy).
// map: §7.5 | A2 | runs-clean | h625 | agora #173: closure binding in a literal through a generic: env copy leaks
: H { ( @ i ) cb i pad }

@ id [T] T v → T { ^ v }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : H h ( id [H] @ H { f 0 } )
    : ( @ i ) c . h cb
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
