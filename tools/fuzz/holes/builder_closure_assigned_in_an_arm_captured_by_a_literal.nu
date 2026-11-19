// builder_closure_assigned_in_an_arm_captured_by_a_literal: a builder's closure assigned in an arm, captured by a literal and run beside a view of xs
// Closed (agora #838): the body's run of a captured closure is noted on the roots of what that closure does under any name it has (__clo_run_attr): a copy `: d c` or an arm's `= d c` reaches c's effects through its node, as a run of d itself does; a builder's placeholder is noted into the literal's effects too.
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (40), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a builder's closure assigned in an arm, captured by a literal and run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

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
