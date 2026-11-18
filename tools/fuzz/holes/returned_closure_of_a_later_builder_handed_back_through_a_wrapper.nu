// returned_closure_of_a_later_builder_handed_back_through_a_wrapper: a wrapper hands back what a builder declared below it returns; the result grows its captured argument while a view lives
// Closed (agora #813): a call of a builder whose answer is not there yet — compiled below its caller, a generic instance — gives the binding of its result placeholders, one per argument (__rce_pending, __rce_placeholders); a run of it is a `pendrce` row, expanded at the walk, which is parked until the module has compiled, into the rows the builder's `retcloeff` gives (__bck_rce_expand), as a builder above its caller does. A wrapper handing it back carries the placeholders in its own answer.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (11, not 7).
// map: §2.10 | A2 | rejected | - | agora #813: a wrapper hands back a later builder's growing closure, run beside a view
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

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }
