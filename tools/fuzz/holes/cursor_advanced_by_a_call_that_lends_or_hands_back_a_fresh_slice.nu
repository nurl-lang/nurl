// cursor_advanced_by_a_call_that_lends_or_hands_back_a_fresh_slice: split-style loop where the cursor advances through a call that answers ownership per call; the piece copied before the advance is read after it.
// Closed: BCK_MAYBE_OWNED reaches every place a value the binding owns does: a binding that may own its value is released at its scope's end (bck_scope_drop, bck_ids_end), a `let` / `=` whose value may be its own and also borrows (a join with a fresh arm, a guarded call) makes it maybe-owned (bck_may_own_row), and so does a closure that runs and gives it a new value (`@assign`).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a split loop advancing its cursor through a call that answers ownership per call
$ `stdlib/core/string.nu`

@ next_of s x i k → s {
    ? > k 0 { ^ ( nurl_str_slice x 1 - ( nurl_str_len x ) 1 ) } {}
    ^ x
}

@ rows String src → i {
    : ~ s rest ( string_data src )
    : ~ i n 0
    : ~ i k 0
    ~ > ( nurl_str_len rest ) 30 {
        : s nm rest
        = rest ( next_of rest 1 )
        = n + n ( nurl_str_len nm )
        = k + k 1
    }
    ^ n
}

@ main → i {
    : String s ( string_from `abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ` )
    ( nurl_print_int ( rows s ) ) ( nurl_print `\n` )
    ^ 0
}
