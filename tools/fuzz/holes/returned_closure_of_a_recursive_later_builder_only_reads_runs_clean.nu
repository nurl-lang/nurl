// returned_closure_of_a_recursive_later_builder_only_reads_runs_clean: the guard of returned_closure_of_a_recursive_later_builder_grows_beside_a_view: the closure only reads
// Closed (agora #813): the closure only reads what it captured; nothing is refused.
// main 431ca15e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #813: a recursive later builder, a reading closure run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( rb xs 3 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ rb ( Vec u ) x i n → ( @ v ) {
    ? > n 0 { ^ ( rb x - n 1 ) } {}
    ^ \ → v { ( nurl_println_int # i ( vec_len [u] x ) ) }
}
