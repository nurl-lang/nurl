// cursor_resliced_in_a_loop_piece_read_first_runs_clean: the shape cursor_over_a_local_view_resliced_in_a_loop must keep: the piece is read before `= rest …`, so nothing it points into is gone yet (nurlc's own unused-import lint, fixed to this order).
// Closed: a binding that is a borrow on one path into a merge and its own value on another (a cursor a loop re-points at a fresh slice, a `?` / `??` arm that gives it one) joins to BCK_MAYBE_OWNED, not to a plain borrow: re-pointing it releases what it owned there, so what was borrowed from it ends (bck_borrow_sweep), and a copy of it borrows it as well as what it borrows (bck_sx_name, bck_borrow_owners).
// main 4f15689: accepted; ran clean.
// map: StmtT.assign | A1 | runs-clean | - | the split loop that reads each piece before the cursor moves on
$ `stdlib/core/string.nu`

@ rows String src → i {
    : ~ s rest ( string_data src )
    : ~ i n 0
    ~ != 0 ( nurl_str_len rest ) {
        : i dt ( nurl_str_find rest `\t` )
        : i dl ( nurl_str_len rest )
        : s nm ? < dt 0 rest ( nurl_str_slice rest 0 dt )
        = n + n ( nurl_str_len nm )
        = rest ? < dt 0 `` ( nurl_str_slice rest + dt 1 - dl + dt 1 )
    }
    ^ n
}

@ main → i {
    : String s ( string_from `ab\tcde\tf` )
    ( nurl_print_int ( rows s ) ) ( nurl_print `\n` )
    ^ 0
}
