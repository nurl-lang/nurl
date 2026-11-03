// vec_cursor_given_a_fresh_vec_by_a_closure_that_runs: a Vec-of-String cursor that only borrows; a closure that runs gives it a fresh Vec of its own; a view into its element; fresh re-point; view read.
// Closed: BCK_MAYBE_OWNED reaches every place a value the binding owns does: a binding that may own its value is released at its scope's end (bck_scope_drop, bck_ids_end), a `let` / `=` whose value may be its own and also borrows (a join with a fresh arm, a guarded call) makes it maybe-owned (bck_may_own_row), and so does a closure that runs and gives it a new value (`@assign`).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A1 | rejected | - | a borrowing Vec cursor given a fresh Vec by a closure that runs; a view of its element outlives its next re-point
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a fresh string long enough for a heap buffer` ) )
    ^ v
}

@ pick ( Vec String ) src → i {
    : ~ ( Vec String ) cur src
    : ( @ v ) give \ → v { = cur ( mk ) }
    ( give )
    : s v ( string_data ( vec_at [String] cur 0 ) )
    = cur ( mk )
    ^ ( nurl_str_len v )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `the caller's string, long enough for the heap` ) )
    ( nurl_print_int ( pick v ) ) ( nurl_print `\n` )
    ^ 0
}
