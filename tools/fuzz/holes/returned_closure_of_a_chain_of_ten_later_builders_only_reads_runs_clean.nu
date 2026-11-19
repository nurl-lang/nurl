// returned_closure_of_a_chain_of_ten_later_builders_only_reads_runs_clean: the guard of returned_closure_of_a_chain_of_ten_later_builders_grows_beside_a_view: the last closure only reads
// Closed (agora #813): the closure only reads what it captured; nothing is refused.
// main 431ca15e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: a chain of ten later builders, a reading closure run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( b0 xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ b0 ( Vec u ) x → ( @ v ) { ^ ( b1 x ) }

@ b1 ( Vec u ) x → ( @ v ) { ^ ( b2 x ) }

@ b2 ( Vec u ) x → ( @ v ) { ^ ( b3 x ) }

@ b3 ( Vec u ) x → ( @ v ) { ^ ( b4 x ) }

@ b4 ( Vec u ) x → ( @ v ) { ^ ( b5 x ) }

@ b5 ( Vec u ) x → ( @ v ) { ^ ( b6 x ) }

@ b6 ( Vec u ) x → ( @ v ) { ^ ( b7 x ) }

@ b7 ( Vec u ) x → ( @ v ) { ^ ( b8 x ) }

@ b8 ( Vec u ) x → ( @ v ) { ^ ( b9 x ) }

@ b9 ( Vec u ) x → ( @ v ) { ^ ( b10 x ) }

@ b10 ( Vec u ) x → ( @ v ) { ^ \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) } }
