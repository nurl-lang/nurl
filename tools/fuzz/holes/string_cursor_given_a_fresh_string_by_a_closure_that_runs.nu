// string_cursor_given_a_fresh_string_by_a_closure_that_runs: a String cursor over a param that only borrows; a closure that runs gives it a String of its own; a view of it; fresh re-point; view read.
// Closed: BCK_MAYBE_OWNED reaches every place a value the binding owns does: a binding that may own its value is released at its scope's end (bck_scope_drop, bck_ids_end), a `let` / `=` whose value may be its own and also borrows (a join with a fresh arm, a guarded call) makes it maybe-owned (bck_may_own_row), and so does a closure that runs and gives it a new value (`@assign`).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A1 | rejected | - | a borrowing String cursor given a fresh String by a closure that runs; a view of it outlives its next re-point
$ `stdlib/core/string.nu`

@ pick String src → i {
    : ~ String cur src
    : ( @ v ) give \ → v { = cur ( string_from `a fresh string long enough for a heap buffer` ) }
    ( give )
    : s v ( string_data cur )
    = cur ( string_from `another fresh string long enough for the heap` )
    ^ ( nurl_str_len v )
}

@ main → i {
    : String s ( string_from `the caller's string, long enough for the heap` )
    ( nurl_print_int ( pick s ) ) ( nurl_print `\n` )
    ^ 0
}
