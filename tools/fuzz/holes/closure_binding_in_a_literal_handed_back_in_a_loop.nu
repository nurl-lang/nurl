// closure_binding_in_a_literal_handed_back_in_a_loop: agora #173 — a closure binding stored into a literal field gets a copy of its env, which nothing dropped when the literal was a call's temporary (closure_binding_in_a_literal_handed_back_in_a_loop).
// Closed: the literal owns that copy and drops it with the rest (gen_agg_lit, __ao_cloid; agora #173).
// v0.80.0: accepted; LeakSanitizer reported the env copy (nurl_closure_own_copy).
// map: §7.5 | A2 | runs-clean | h626 | agora #173: closure binding in a literal handed back in a loop: env copy leaks
: H { ( @ i ) cb i pad }

@ pass H h → H { ^ h }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : ~ i n 0
    : ~ i acc 0
    ~ < n 50 {
        : H h ( pass @ H { f n } )
        : ( @ i ) c . h cb
        = acc + acc ( c )
        = n + n 1
    }
    ( nurl_println_int acc )
    ^ 0
}
