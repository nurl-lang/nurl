// returned_closure_of_a_later_builder_handed_back_through_a_wrapper_only_reads_runs_clean: the guard of returned_closure_of_a_later_builder_handed_back_through_a_wrapper: the closure only reads
// Closed (agora #813): the closure only reads what it captured, so its effects (none) leave the view be; nothing is refused.
// main e35ded15: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: a wrapper hands back a later builder's reading closure, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ wrap ( Vec u ) x → ( @ v ) { ^ ( mk x ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( wrap xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) } }
