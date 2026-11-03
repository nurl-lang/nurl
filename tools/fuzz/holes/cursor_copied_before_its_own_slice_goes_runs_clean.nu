// cursor_copied_before_its_own_slice_goes_runs_clean: the shape cursor_given_its_own_slice_on_one_arm must keep: the copy owns its bytes.
// Closed: a binding that is a borrow on one path into a merge and its own value on another (a cursor a loop re-points at a fresh slice, a `?` / `??` arm that gives it one) joins to BCK_MAYBE_OWNED, not to a plain borrow: re-pointing it releases what it owned there, so what was borrowed from it ends (bck_borrow_sweep), and a copy of it borrows it as well as what it borrows (bck_sx_name, bck_borrow_owners).
// main 4f15689: accepted; ran clean.
// map: StmtT.assign | A1 | runs-clean | - | a cursor that may own its slice, copied into a String of its own before it is re-pointed
$ `stdlib/core/string.nu`

@ pick String src b own → i {
    : ~ s cur ( string_data src )
    ? own { = cur ( nurl_str_slice cur 1 2 ) } {}
    : String nm ( string_from cur )
    = cur ( nurl_str_slice `xyz` 0 1 )
    ^ ( string_len nm )
}

@ main → i {
    : String s ( string_from `abcdef` )
    ( nurl_print_int ( pick s T ) ) ( nurl_print `\n` )
    ^ 0
}
