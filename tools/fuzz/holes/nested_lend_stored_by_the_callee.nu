// nested_lend_stored_by_the_callee: a view a nested call lends (`( string_data x )`), handed to a callee that stores it in what it returns, was not a view of `x` in the result: the borrow walk counted only the views among a stored argument's own names, not what a call there lends, so the caller released `x` and read the stored view.
// Closed: a call's result stored by a callee is the value stored — its own lends count in full (bck_sx_ev); only a closure literal, which copies what it views when stored, is left out.
// main (before this PR): AddressSanitizer reported heap-use-after-free printing the stored view.
// map: §2.10 | A2 | rejected | h304 | a view a nested call lends (string_data x), stored by the callee in what it returns, was not a view of x in the result
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wrapv s a → ( Vec s ) { : ( Vec s ) out ( vec_new [s] ) ( vec_push [s] out a ) ^ out }

@ main → i {
    : String x ( string_from `abcd` )
    : ( Vec s ) w ( wrapv ( string_data x ) )
    ( string_free x )
    ( nurl_println ( vec_at [s] w 0 ) )
    ^ 0
}
