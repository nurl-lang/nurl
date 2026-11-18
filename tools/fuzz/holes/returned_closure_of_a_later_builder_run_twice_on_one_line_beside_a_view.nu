// returned_closure_of_a_later_builder_run_twice_on_one_line_beside_a_view: a later builder's closure run, a view of xs taken, and the closure run again, all on one line; the view read after
// Closed (agora #813): each run's placeholder row is expanded on its own (__bck_rce_run), so the second run on the line ends the view as the first would.
// main 431ca15e: accepted; the read after the second run reads 7 out of the freed buffer, and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #813: a later builder's closure run twice on one line, a view of its argument taken between the runs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    ( c ) : ( Slice u ) sl ( slice_from_vec [u] xs ) ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { : ~ i k 0 ~ < k 5000 { ( vec_push [u] x 1 ) = k + k 1 } } }
