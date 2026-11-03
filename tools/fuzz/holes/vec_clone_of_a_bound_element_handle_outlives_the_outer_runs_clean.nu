// vec_clone_of_a_bound_element_handle_outlives_the_outer_runs_clean: vec_clone of a binding of an element of a ( Vec ( Vec s ) ), the outer Vec given a new value.
// Kept: a copy of a part of an argument — an element or a field handle, a slice of it — holds what that part holds, not the storage it is in: the held evaluator reads a `retpart` argument as what it holds, a holder that borrows its value depends on what that value holds (its borrow ties it to the rest), and the type-class memo reads `-1` as "ask again" (__sym_vint).
// main 836c0e9: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | Family G review: vec_clone of a binding of an element of a ( Vec ( Vec s ) ), the outer Vec given a new value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String b ( string_from `a string that outlives every reader here` )
    : ~ ( Vec s ) keep ( vec_new [s] )
    : ~ ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    : ( Vec s ) inner ( vec_new [s] )
    ( vec_push [s] inner ( string_data b ) )
    ( vec_push [( Vec s )] vv inner )
    : ( Vec s ) e ( vec_at [( Vec s )] vv 0 )
    = keep ( vec_clone [s] e )
    = vv ( vec_new [( Vec s )] )
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
