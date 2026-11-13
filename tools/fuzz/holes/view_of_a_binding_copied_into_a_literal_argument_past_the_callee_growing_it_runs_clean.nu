// view_of_a_binding_copied_into_a_literal_argument_past_the_callee_growing_it_runs_clean: `( g @ X { ( vec_clone xs ) } )` with g growing `. x v`, a slice of xs read after
// Kept: a literal argument hands the callee's change of it to the bindings it takes, not to those a call in it reads — `( vec_clone xs )` is a copy (agora #799's review).
// main 0aeaa321: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #799: a copy of a binding in a literal argument whose callee grows it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }

@ g X x → v { ( vec_reserve [u] . x v 4096 ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( g @ X { ( vec_clone [u] xs ) } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
