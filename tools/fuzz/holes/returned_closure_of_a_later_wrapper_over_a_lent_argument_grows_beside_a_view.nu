// returned_closure_of_a_later_wrapper_over_a_lent_argument_grows_beside_a_view: a later wrapper is handed a value lent out of xs, `( wrap ( idv xs ) )`; its closure grows it while a view of xs lives
// Closed (agora #813): a row a placeholder expands to may be a placeholder in turn (a builder handing back another's closure, a forwarder's): __bck_rce_expand expands again until none is left. A forwarder not compiled yet gets `rcq#` placeholders for the closures handed to it, kept where its final `retclo` hands them back; a value lent out of the argument gives a `pendlend` row (CodeRabbit on github#1950).
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (185, not 7).
// map: §2.10 | A2 | rejected | - | agora #813: a later wrapper over a lent argument, the closure run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( wrap ( idv xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ idv ( Vec u ) v → ( Vec u ) { ^ v }

@ wrap ( Vec u ) x → ( @ v ) { ^ ( mk x ) }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }
