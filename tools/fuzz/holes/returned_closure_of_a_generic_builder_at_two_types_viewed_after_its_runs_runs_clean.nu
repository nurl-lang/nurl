// returned_closure_of_a_generic_builder_at_two_types_viewed_after_its_runs_runs_clean: the guard of the two generic-instance probes: both closures run before any view is taken
// Closed (agora #813): no view lives across a run; nothing is refused.
// main e35ded15: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: a generic builder at two types, both run before the views
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 5 )
    : ( @ v ) d ( mk [i] ys )
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk [u] xs )
    ( c )
    ( d )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( Slice i ) sm ( slice_from_vec [i] ys )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ( nurl_println_int ( slice_at [i] sm 0 ) )
    ^ 0
}

@ mk [T] ( Vec T ) x → ( @ v ) { ^ \ → v { ( vec_reserve [T] x 4096 ) } }
