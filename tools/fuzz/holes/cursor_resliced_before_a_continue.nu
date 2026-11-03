// cursor_resliced_before_a_continue: `rest` starts as a view, and each round gives it a slice of its own (one path leaves by `continue`). A copy taken at the top of a later round points into that slice; re-pointing `rest` frees it before the copy is read.
// Closed: a binding that is a borrow on one path into a merge and its own value on another (a cursor a loop re-points at a fresh slice, a `?` / `??` arm that gives it one) joins to BCK_MAYBE_OWNED, not to a plain borrow: re-pointing it releases what it owned there, so what was borrowed from it ends (bck_borrow_sweep), and a copy of it borrows it as well as what it borrows (bck_sx_name, bck_borrow_owners).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a cursor re-pointed at a fresh slice on a continue path and at the loop's end: a copy taken at the top of the next round is read after the re-point
$ `stdlib/core/string.nu`

@ rows String src → i {
    : ~ s rest ( string_data src )
    : ~ i n 0
    : ~ i k 0
    ~ < k 4 {
        = k + k 1
        : s nm rest
        ? == k 2 { = rest ( nurl_str_slice `qwerty` 0 3 ) = n + n ( nurl_str_len nm ) continue } {}
        = rest ( nurl_str_slice `zz` 0 1 )
        = n + n ( nurl_str_len nm )
    }
    ^ n
}

@ main → i {
    : String s ( string_from `abcdef` )
    ( nurl_print_int ( rows s ) ) ( nurl_print `\n` )
    ^ 0
}
