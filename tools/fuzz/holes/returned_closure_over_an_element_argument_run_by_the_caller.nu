// returned_closure_over_an_element_argument_run_by_the_caller: `( mk ( vec_at vv 0 ) )`, the closure reserving its capture, run after a slice of the element
// Closed: a closure a function hands back carries its effects on the arguments it captured to the caller's binding — through a field-path or lending argument, a join or a block, an `=`, and a by-reference capture re-pointed before it runs (agora #802).
// main b73574d9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #802: a returned closure over an element lent as the argument
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
    : ( @ v ) c ( mk ( vec_at [( Vec u )] vv 0 ) )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
