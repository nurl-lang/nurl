// closure_reading_a_captured_parameter_runs_clean: a closure that reads `( vec_len x )` of a captured parameter, run in its function
// Kept: a closure that only reads what it captured, or its own parameter, changes nothing of the caller's (agora #656).
// main 820aafb4: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #656: a closure that only reads a captured parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ w ( Vec u ) x → v {
    : ( @ v ) c \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) }
    ( c )
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( w xs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
