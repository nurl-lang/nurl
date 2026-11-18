// returned_closure_of_a_recursive_later_builder_grows_beside_a_view: a builder declared below its caller that hands back its own call's closure; the closure grows its argument while a view lives
// Closed (agora #813): a row a placeholder expands to may be a placeholder in turn (a builder handing back another's closure, a forwarder's): __bck_rce_expand expands again until none is left. A forwarder not compiled yet gets `rcq#` placeholders for the closures handed to it, kept where its final `retclo` hands them back; a value lent out of the argument gives a `pendlend` row (CodeRabbit on github#1950).
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (228, not 7).
// map: §2.10 | A2 | rejected | - | agora #813: a recursive later builder, the closure run beside a view
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
    ^ \ → v { ( vec_reserve [u] x 4096 ) }
}
