// cursor_given_a_join_of_a_fresh_slice_or_a_view: cursor assigned a join whose one arm is a fresh slice and the other a view; copy; fresh re-point; copy read.
// Closed: BCK_MAYBE_OWNED reaches every place a value the binding owns does: a binding that may own its value is released at its scope's end (bck_scope_drop, bck_ids_end), a `let` / `=` whose value may be its own and also borrows (a join with a fresh arm, a guarded call) makes it maybe-owned (bck_may_own_row), and so does a closure that runs and gives it a new value (`@assign`).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a cursor given `? c ( slice ) ( view )`, copied, re-pointed: the copy is read
$ `stdlib/core/string.nu`

@ pick String src b own → i {
    : ~ s cur ( string_data src )
    = cur ? own ( nurl_str_slice cur 1 40 ) ( string_data src )
    : s nm cur
    = cur ( nurl_str_slice `zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz` 0 35 )
    ^ ( nurl_str_len nm )
}

@ main → i {
    : String s ( string_from `abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ` )
    ( nurl_print_int ( pick s T ) ) ( nurl_print `\n` )
    ^ 0
}
