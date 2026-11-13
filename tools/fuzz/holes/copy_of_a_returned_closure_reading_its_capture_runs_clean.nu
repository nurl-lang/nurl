// copy_of_a_returned_closure_reading_its_capture_runs_clean: a copy of a returned closure that only reads, run after a slice
// Kept: a copy of a returned closure that only reads changes nothing of the caller's (agora #817).
// main 0aeaa321 (+#1846): accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #817: a copy of a read-only returned closure
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ i ) { ^ \ → i { ^ # i ( vec_len [u] x ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ i ) c ( mk xs )
    : ( @ i ) d c
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( nurl_println_int ( d ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
