// forwarder_hands_back_its_closure_parameter_through_a_literals_call_reads_runs_clean: the guard of forwarder_hands_back_its_closure_parameter_through_a_literals_call: the closure only reads its captured argument
// Closed (agora #838): the closure only reads what it captured, so its effects (none) leave the view be; nothing is refused.
// main cfbd6b0e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #838: a forwarder handing back a reading closure through a literal's call, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) } }

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
