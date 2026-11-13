// growing_closure_chosen_by_a_ternary_then_run_is_refused: a closure growing its captured Vec, run through a copy: `: d ? k c c0  ( d )`, a Slice of the Vec read after
// Closed: agora #686, a closure's effects follow its node, not only the name its literal was bound to.
// main 21774dd7: accepted (ASan: heap-use-after-free).
// map: §2.10 | A2 | rejected | - | agora #686: a growing closure chosen by a ternary, then run ends the views of what it captured
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d ? k c c0
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
