// generic_identity_of_a_reading_builder_call_runs_clean: the guard of generic_identity_of_a_builder_call: the closure only reads its captured argument
// Closed (agora #813): the closure only reads what it captured, so its effects (none) leave the view be; nothing is refused.
// main 431ca15e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: `( idg [( @ v )] ( mk xs ) )` with a reading closure, run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ idg [T] T x → T { ^ x }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( idg [( @ v )] ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
