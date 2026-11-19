// returned_closure_of_a_later_builder_run_inside_another_literal: a later builder's returned closure, run inside another literal that runs while a view lives
// Closed (agora #813): a call of a builder whose answer is not there yet — compiled below its caller, a generic instance — gives the binding of its result placeholders, one per argument (__rce_pending, __rce_placeholders); a run of it is a `pendrce` row, expanded at the walk, which is parked until the module has compiled, into the rows the builder's `retcloeff` gives (__bck_rce_expand), as a builder above its caller does.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (163, not 7).
// map: §2.10 | A2 | rejected | - | agora #813: a returned closure of a builder below its caller, run inside another literal, beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( @ v ) d \ → v { ( c ) }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }
