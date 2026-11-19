// builder_closure_assigned_in_an_arm_captured_by_a_literal_reads_runs_clean: the guard of builder_closure_assigned_in_an_arm_captured_by_a_literal: the closure only reads its captured argument
// Closed (agora #838): the closure only reads what it captured, so its effects (none) leave the view be; nothing is refused.
// main 431ca15e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #838: a reading builder closure assigned in an arm, captured by a literal, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ~ ( @ v ) d \ → v {}
    ? > ( vec_len [u] xs ) 0 { = d c } {}
    : ( @ v ) e \ → v { ( d ) }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( e )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
