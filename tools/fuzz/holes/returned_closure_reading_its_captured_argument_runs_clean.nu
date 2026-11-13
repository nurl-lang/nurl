// returned_closure_reading_its_captured_argument_runs_clean: a returned closure that only reads `( vec_len x )`, run after the caller took a slice
// Kept: a returned closure that only reads what it captured ends nothing of the caller's (agora #802).
// main b73574d9: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #802: a returned closure that only reads its capture
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ i ) { ^ \ → i { ^ # i ( vec_len [u] x ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ i ) c ( mk xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( nurl_println_int ( c ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
