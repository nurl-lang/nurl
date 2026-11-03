// cursor_given_its_own_slice_on_one_arm: `cur` views a String; one arm of a `?` gives it a slice of its own, the other a view again. A copy taken past the join points into that slice on the first path, and `= cur …` frees it there.
// Closed: a binding that is a borrow on one path into a merge and its own value on another (a cursor a loop re-points at a fresh slice, a `?` / `??` arm that gives it one) joins to BCK_MAYBE_OWNED, not to a plain borrow: re-pointing it releases what it owned there, so what was borrowed from it ends (bck_borrow_sweep), and a copy of it borrows it as well as what it borrows (bck_sx_name, bck_borrow_owners).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a cursor given its own slice on one arm of a ?, copied, then re-pointed: the copy is read
$ `stdlib/core/string.nu`

@ pick String src b own → i {
    : ~ s cur ( string_data src )
    ? own { = cur ( nurl_str_slice cur 1 2 ) } { = cur ( string_data src ) }
    : s nm cur
    = cur ( nurl_str_slice `xyz` 0 1 )
    ^ ( nurl_str_len nm )
}

@ main → i {
    : String s ( string_from `abcdef` )
    ( nurl_print_int ( pick s T ) ) ( nurl_print `\n` )
    ^ 0
}
