// view_of_a_binding_moved_into_an_option_literal_argument_past_the_callee_growing_it: `( w @ ?( Vec u ) { T xs } )` with w growing the payload, a slice of xs read after
// Closed: a literal written as an argument hands what the callee does to it to the bindings it takes (agora #799's `pendlit`; agora #816).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #816: a view of a binding moved into an option literal argument
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ w ? ( Vec u ) o → v {
    ?? o { T p → ( vec_reserve [u] p 4096 ) F → {} }
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( w @ ?( Vec u ) { T xs } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
