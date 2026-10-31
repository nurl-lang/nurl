// two_closure_fields_of_a_literal_picked_and_read: agora #173 — a closure binding stored into a literal field gets a copy of its env, which nothing dropped when the literal was a call's temporary (two_closure_fields_of_a_literal_picked_and_read).
// Closed: the literal owns that copy and drops it with the rest (gen_agg_lit, __ao_cloid; agora #173).
// v0.80.0: accepted; LeakSanitizer reported the env copy (nurl_closure_own_copy).
// map: §7.5 | A2 | runs-clean | h628 | agora #173: two closure fields of a literal picked and read: env copy leaks
: H2 { ( @ i ) a ( @ i ) b }

@ pick H2 h → ( @ i ) { ^ . h a }

@ both H2 h → i { : ( @ i ) a . h a : ( @ i ) b . h b ^ + ( a ) ( b ) }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : ( @ i ) p ( pick @ H2 { f \ → i { ^ 7 } } )
    ( nurl_println_int ( p ) )
    ( nurl_println_int ( both @ H2 { f f } ) )
    ^ 0
}
