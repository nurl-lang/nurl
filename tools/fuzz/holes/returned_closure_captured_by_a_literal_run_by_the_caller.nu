// returned_closure_captured_by_a_literal_run_by_the_caller: `: c ( mk xs )`, `: d \ → v { ( c ) }`, a slice of xs, then `( d )`
// Closed: a closure a call hands back, captured by a literal, makes the literal reach the bindings its effects name — running it in the body does to them what it does (__clo_eff_roots into the literal's captures; agora #817's review).
// main 006aa3e8: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #817: a returned closure captured by a literal and run by the caller
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Vec u ) ys ( vec_new [u] )
    : ( @ v ) c ( mk xs )
    : ( @ v ) d \ → v { ( c ) }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
