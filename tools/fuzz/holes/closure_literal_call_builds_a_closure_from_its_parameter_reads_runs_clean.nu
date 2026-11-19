// closure_literal_call_builds_a_closure_from_its_parameter_reads_runs_clean: the guard of closure_literal_call_builds_a_closure_from_its_parameter: the closure only reads its captured argument
// Closed (agora #838): the closure only reads what it captured, so its effects (none) leave the view be; nothing is refused.
// main 431ca15e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #838: a literal's call handing back a reading closure over its parameter, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ ( @ v ) ( Vec u ) ) g \ ( Vec u ) p → ( @ v ) { ^ ( mk p ) }
    : ( @ v ) d ( g xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
