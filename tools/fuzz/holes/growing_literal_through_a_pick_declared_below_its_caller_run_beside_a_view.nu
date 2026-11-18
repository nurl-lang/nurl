// growing_literal_through_a_pick_declared_below_its_caller_run_beside_a_view: a local growing literal handed through `pick`, declared below its caller, then run while a view lives
// Closed (agora #813): a row a placeholder expands to may be a placeholder in turn (a builder handing back another's closure, a forwarder's): __bck_rce_expand expands again until none is left. A forwarder not compiled yet gets `rcq#` placeholders for the closures handed to it, kept where its final `retclo` hands them back; a value lent out of the argument gives a `pendlend` row (CodeRabbit on github#1950).
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (46, not 7).
// map: §2.10 | A2 | rejected | - | agora #813: a growing literal through a pick declared below, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( pick \ → v { ( vec_reserve [u] xs 4096 ) } )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ pick ( @ v ) f → ( @ v ) { ^ f }
