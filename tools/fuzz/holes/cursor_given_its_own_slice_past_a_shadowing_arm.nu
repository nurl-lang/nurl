// cursor_given_its_own_slice_past_a_shadowing_arm: as cursor_given_its_own_slice_on_one_arm, with a later arm that binds a `cur` of its own: the outer `cur`'s state comes back as it was (bck_st_raw), "may own" included.
// Closed: a binding that is a borrow on one path into a merge and its own value on another (a cursor a loop re-points at a fresh slice, a `?` / `??` arm that gives it one) joins to BCK_MAYBE_OWNED, not to a plain borrow: re-pointing it releases what it owned there, so what was borrowed from it ends (bck_borrow_sweep), and a copy of it borrows it as well as what it borrows (bck_sx_name, bck_borrow_owners).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a cursor that may own its slice, past an arm that shadows its name: the copy is read after the re-point
$ `stdlib/core/string.nu`

@ pick String src b own → i {
    : ~ s cur ( string_data src )
    ? own { = cur ( nurl_str_slice cur 1 2 ) } {}
    ? own {
        : s cur `inner`
        ( nurl_print cur )
    } {}
    : s nm cur
    = cur ( nurl_str_slice `xyz` 0 1 )
    ^ ( nurl_str_len nm )
}

@ main → i {
    : String s ( string_from `abcdef` )
    ( nurl_print_int ( pick s T ) ) ( nurl_print `\n` )
    ^ 0
}
