// cursor_that_may_own_its_slice_released_at_the_loop_body_end: a cursor declared in a loop body, given its own slice on some rounds (it may own its value at the body's end); an outer cursor is pointed at it; the next round's declaration releases the slice; the outer cursor is read at the top of that round.
// Closed: BCK_MAYBE_OWNED reaches every place a value the binding owns does: a binding that may own its value is released at its scope's end (bck_scope_drop, bck_ids_end), a `let` / `=` whose value may be its own and also borrows (a join with a fresh arm, a guarded call) makes it maybe-owned (bck_may_own_row), and so does a closure that runs and gives it a new value (`@assign`).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A1 | rejected | - | a loop-local cursor that may own its slice is released at the body end; an outer cursor pointed at it is read next round
$ `stdlib/core/string.nu`

@ rows String src → i {
    : ~ s keep ( string_data src )
    : ~ i n 0
    : ~ i k 0
    ~ < k 3 {
        = n + n ( nurl_str_len keep )
        : ~ s cur ( string_data src )
        ? == k 0 { = cur ( nurl_str_slice cur 1 40 ) } {}
        = keep cur
        = k + k 1
    }
    ^ n
}

@ main → i {
    : String s ( string_from `abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ` )
    ( nurl_print_int ( rows s ) ) ( nurl_print `\n` )
    ^ 0
}
