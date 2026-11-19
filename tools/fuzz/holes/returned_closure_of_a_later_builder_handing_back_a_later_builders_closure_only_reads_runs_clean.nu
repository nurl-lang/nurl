// returned_closure_of_a_later_builder_handing_back_a_later_builders_closure_only_reads_runs_clean: the guard of returned_closure_of_a_later_builder_handing_back_a_later_builders_closure_grows_beside_a_view: the closure only reads
// Closed (agora #813): the closure only reads what it captured; nothing is refused.
// main 431ca15e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: nested later builders, a reading closure run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( outer xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ outer ( Vec u ) x → ( @ v ) { ^ ( inner x ) }

@ inner ( Vec u ) x → ( @ v ) { ^ \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) } }
