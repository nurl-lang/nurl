// returned_closure_over_a_block_ending_in_a_lend_run_by_the_caller: `( mk { … ( vec_at vv 0 ) } )`, a slice of that element, then the closure run
// Closed: a block argument whose value is a call's lends what that call lends, as the call written there does (__effr_entry; agora #817's review).
// main 006aa3e8: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #817: a returned closure over a block ending in a lending call
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( @ v ) c ( mk { ( nurl_println_int 1 ) ( vec_at [( Vec u )] vv 0 ) } )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
