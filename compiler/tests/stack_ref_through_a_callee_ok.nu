// stack_ref_through_a_callee_ok.nu — a closure that captured a local by
// reference, handed through a callee that returns it (a `??` payload, a
// closure field) and called while the frame lives (agora #154). It runs
// clean.

: H { ( @ i ) cb i pad }

@ unwrap ? ( @ i ) o → ( @ i ) { ^ ?? o { T g → g F → \ → i { ^ 0 } } }

@ pick H h → ( @ i ) { ^ . h cb }

@ main → i {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : ?( @ i ) o @ ?( @ i ) { T f }
    : ( @ i ) g ( unwrap o )
    ( nurl_println_int ( g ) )
    : H h @ H { f 0 }
    : ( @ i ) p ( pick h )
    ( nurl_println_int ( p ) )
    ^ 0
}
