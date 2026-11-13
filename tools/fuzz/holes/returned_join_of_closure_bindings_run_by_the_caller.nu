// returned_join_of_closure_bindings_run_by_the_caller: `^ ? k c1 c2` of closure bindings that grow the parameter
// Closed: a closure a function hands back carries its effects on the arguments it captured to the caller's binding — through a field-path or lending argument, a join or a block, an `=`, and a by-reference capture re-pointed before it runs (agora #802).
// main b73574d9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #802: a returned join of closure bindings
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ mk ( Vec u ) x b k → ( @ v ) {
    : ( @ v ) c1 \ → v { ( vec_reserve [u] x 4096 ) }
    : ( @ v ) c2 \ → v {}
    ^ ? k c1 c2
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs T )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
