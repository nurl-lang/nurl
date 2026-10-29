// diag_stack_ref_through_a_callee.nu — a closure that captured a local by
// reference, handed back through a callee that returns a `??` payload of
// its parameter, or a closure field of it (agora #154): the result still
// points into this frame, so returning or storing it dangles.

$ `stdlib/core/vec.nu`

: H { ( @ i ) cb i pad }

@ unwrap ? ( @ i ) o → ( @ i ) { ^ ?? o { T g → g F → \ → i { ^ 0 } } }

@ pick H h → ( @ i ) { ^ . h cb }

@ through_a_payload → ( @ i ) {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    ^ ( unwrap @ ?( @ i ) { T f } )
}

@ through_a_field → ( @ i ) {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : ( @ i ) g ( pick @ H { f 0 } )
    ^ g
}

@ pushed_into_a_param inout ( Vec ( @ i ) ) out → v {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    ( vec_push [( @ i )] out ( pick @ H { f 0 } ) )
}

@ main → i { ^ 0 }
