// forwarder_binds_a_literals_call_handing_back_its_closure_parameter: fw binds `( g )` and hands the binding back, g a literal handing back fw's closure parameter; `( fw ( mk xs ) )` run beside a view of xs
// Closed (agora #838): the literal records which closure it hands back by the name the call sees (`lv#`: its capture f); a call of it lends the result from that name, so fw's `^` records f in its `retclo` and the caller's binding gets the builder's effects. A binding of the call is lent from it too (`__clolend`).
// main cfbd6b0e: accepted; the read after the run prints a freed buffer's bytes (215), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a forwarder binding a literal's call that hands back its closure parameter, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ fw ( @ v ) f → ( @ v ) {
    : ( @ ( @ v ) ) g \ → ( @ v ) { ^ f }
    : ( @ v ) h ( g )
    ^ h
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
