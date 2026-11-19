// returned_closure_of_a_later_builder_never_run_runs_clean: a later builder's closure is bound and never run, beside a view
// Closed (agora #813): a placeholder that is never run makes no row; the walk parks until the module has compiled, as for any pending row, and reports nothing.
// main e35ded15: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: a later builder's closure bound and never run
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }
