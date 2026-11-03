// slice_to_vec_of_a_slice_of_a_vec_outlives_the_vec_runs_clean: slice_to_vec of a Slice of a Vec of views outlives the Vec; the strings outlive both.
// Kept: a copy of a part of an argument — an element or a field handle, a slice of it — holds what that part holds, not the storage it is in: the held evaluator reads a `retpart` argument as what it holds, a holder that borrows its value depends on what that value holds (its borrow ties it to the rest), and the type-class memo reads `-1` as "ask again" (__sym_vint).
// main 836c0e9: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | Family G review: slice_to_vec of a Slice of a Vec of views outlives the Vec; the strings outlive both
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    : String b ( string_from `a string that outlives every reader here` )
    {
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( slice_to_vec [s] ( slice_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
