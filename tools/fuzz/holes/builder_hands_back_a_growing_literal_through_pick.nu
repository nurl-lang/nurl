// builder_hands_back_a_growing_literal_through_pick: a builder hands back its growing literal through `pick`, which returns its argument; the result runs while a view lives
// Closed (agora #813): a callee that hands back the closure it was handed (`retclo`) hands back its effects too: the literal's effects (`__ce_by_arg`) are the result's, replayed where it runs.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (192, not 7).
// map: §2.10 | A2 | rejected | - | agora #813: a builder hands back its growing literal through `pick` returning its argument, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ pick ( @ v ) f → ( @ v ) { ^ f }

@ mk ( Vec u ) x → ( @ v ) { ^ ( pick \ → v { ( vec_reserve [u] x 4096 ) } ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
