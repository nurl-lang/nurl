// function_handing_back_a_clone_of_its_vec_of_vecs_element_runs_clean: a function handing back vec_clone of the first element of its ( Vec ( Vec s ) ) parameter.
// Kept: a copy of a part of an argument — an element or a field handle, a slice of it — holds what that part holds, not the storage it is in: the held evaluator reads a `retpart` argument as what it holds, a holder that borrows its value depends on what that value holds (its borrow ties it to the rest), and the type-class memo reads `-1` as "ask again" (__sym_vint).
// main 836c0e9: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | Family G review: a function handing back vec_clone of the first element of its ( Vec ( Vec s ) ) parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec ( Vec s ) ) vv → ( Vec s ) { ^ ( vec_clone [s] ( vec_at [( Vec s )] vv 0 ) ) }

@ main → i {
    : String b ( string_from `a string that outlives every reader here` )
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
        : ( Vec s ) inner ( vec_new [s] )
        ( vec_push [s] inner ( string_data b ) )
        ( vec_push [( Vec s )] vv inner )
        = keep ( first vv )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
