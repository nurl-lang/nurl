// returned_closure_of_a_builder_declared_below_its_caller_grows_beside_a_view: a returned closure growing its captured argument, its builder declared below the caller, run while a view of the argument lives
// Closed (agora #813): a call of a builder whose answer is not there yet — compiled below its caller, a generic instance — gives the binding of its result placeholders, one per argument (__rce_pending, __rce_placeholders); a run of it is a `pendrce` row, expanded at the walk, which is parked until the module has compiled, into the rows the builder's `retcloeff` gives (__bck_rce_expand), as a builder above its caller does.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (196, not 7).
// map: §2.10 | A2 | rejected | - | agora #813: a returned closure growing its captured argument, its builder declared below the caller, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }
