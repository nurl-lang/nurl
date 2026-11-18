// returned_closure_of_a_chain_of_ten_later_builders_grows_beside_a_view: eleven builders declared below their caller, each handing back the next one's closure; the last one's grows its argument while a view lives
// Closed (agora #813): __bck_rce_expand expands a placeholder row again until none is left, any chain length; a row already expanded is dropped (the walk's `rceseen#` keys), so a builder handing back its own closure ends too (CodeRabbit on github#1950).
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (46, not 7).
// map: §2.10 | A2 | rejected | - | agora #813: a chain of ten later builders, the last closure run beside a view
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

@ b10 ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }
