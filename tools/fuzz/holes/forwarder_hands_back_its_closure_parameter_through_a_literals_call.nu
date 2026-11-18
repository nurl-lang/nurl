// forwarder_hands_back_its_closure_parameter_through_a_literals_call: fw hands back `( g )`, g a literal handing back fw's closure parameter it captured; `( fw ( mk xs ) )` run beside a view of xs
// Closed (agora #838): the literal records which closure it hands back by the name the call sees (`lv#`: its capture f); a call of it lends the result from that name, so fw's `^` records f in its `retclo` and the caller's binding gets the builder's effects.
// main cfbd6b0e: accepted; the read after the run prints a freed buffer's bytes (147), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a forwarder handing back its closure parameter through a literal's call, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ fw ( @ v ) f → ( @ v ) {
    : ( @ ( @ v ) ) g \ → ( @ v ) { ^ f }
    ^ ( g )
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( fw ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
