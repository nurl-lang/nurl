// returned_closure_of_a_generic_builders_other_instance_grows_beside_a_view: the same generic builder at two types; the `i` instance's closure grows its argument while a view of it lives
// Closed (agora #813): a call of a builder whose answer is not there yet — compiled below its caller, a generic instance — gives the binding of its result placeholders, one per argument (__rce_pending, __rce_placeholders); a run of it is a `pendrce` row, expanded at the walk into the rows the builder's `retcloeff` gives (__bck_rce_expand). Each instance's rows come from that instance's answer.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (23024970651, not 5).
// map: §2.10 | A2 | rejected | - | agora #813: a generic builder's second instance run beside a view of its argument
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk [u] xs )
    ( c )
    : ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 5 )
    : ( @ v ) d ( mk [i] ys )
    : ( Slice i ) sm ( slice_from_vec [i] ys )
    ( d )
    ( nurl_println_int ( slice_at [i] sm 0 ) )
    ^ 0
}

@ mk [T] ( Vec T ) x → ( @ v ) { ^ \ → v { ( vec_reserve [T] x 4096 ) } }
