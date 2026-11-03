// cursor_given_a_match_value_of_a_fresh_slice_or_a_view: s cursor assigned a ?? whose T arm is a fresh slice of the payload length and the F arm a view; copy; fresh re-point; copy read.
// Closed: BCK_MAYBE_OWNED reaches every place a value the binding owns does: a binding that may own its value is released at its scope's end (bck_scope_drop, bck_ids_end), a `let` / `=` whose value may be its own and also borrows (a join with a fresh arm, a guarded call) makes it maybe-owned (bck_may_own_row), and so does a closure that runs and gives it a new value (`@assign`).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a cursor given a `??` value whose T arm is a fresh slice and F arm a view, copied, re-pointed
$ `stdlib/core/string.nu`

@ pick String src ? i k → i {
    : ~ s cur ( string_data src )
    = cur ?? k { T n → ( nurl_str_slice cur 0 n ) F → ( string_data src ) }
    : s nm cur
    = cur ( nurl_str_slice `zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz` 0 35 )
    ^ ( nurl_str_len nm )
}

@ main → i {
    : String s ( string_from `abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ` )
    ( nurl_print_int ( pick s @ ?i { T 40 } ) ) ( nurl_print `\n` )
    ^ 0
}
