// cursor_that_may_own_its_slice_pushed_into_an_inout_vec: MAYBE_OWNED cursor pushed into an inout Vec of views; the function returns (cursor's owned slice freed at exit); caller reads the element.
// Closed: BCK_MAYBE_OWNED reaches every place a value the binding owns does: a binding that may own its value is released at its scope's end (bck_scope_drop, bck_ids_end), a `let` / `=` whose value may be its own and also borrows (a join with a fresh arm, a guarded call) makes it maybe-owned (bck_may_own_row), and so does a closure that runs and gives it a new value (`@assign`).
// main 4f15689: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A1 | rejected | - | a cursor that may own its slice pushed into the caller's inout Vec of views at function exit
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ fill String src inout ( Vec s ) out b own → v {
    : ~ s cur ( string_data src )
    ? own { = cur ( nurl_str_slice cur 1 40 ) } {}
    ( vec_push [s] out cur )
}

@ main → i {
    : String s ( string_from `abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ` )
    : ~ ( Vec s ) out ( vec_new [s] )
    ( fill s out T )
    ( nurl_print_int ( nurl_str_len ( vec_at [s] out 0 ) ) ) ( nurl_print `\n` )
    ^ 0
}
