// cursor_given_its_own_slice_in_a_match_arm: as cursor_given_its_own_slice_on_one_arm, through a `??` whose `T` arm gives the cursor a slice of its own.
// Closed: a binding that is a borrow on one path into a merge and its own value on another (a cursor a loop re-points at a fresh slice, a `?` / `??` arm that gives it one) joins to BCK_MAYBE_OWNED, not to a plain borrow: re-pointing it releases what it owned there, so what was borrowed from it ends (bck_borrow_sweep), and a copy of it borrows it as well as what it borrows (bck_sx_name, bck_borrow_owners).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: StmtT.assign | A1 | rejected | - | a cursor given its own slice in one arm of a ??, copied, then re-pointed: the copy is read
$ `stdlib/core/string.nu`

@ pick String src ? i k → i {
    : ~ s cur ( string_data src )
    ?? k {
        T n → { = cur ( nurl_str_slice cur 0 n ) }
        F _ → {}
    }
    : s nm cur
    = cur ( nurl_str_slice `xyz` 0 1 )
    ^ ( nurl_str_len nm )
}

@ main → i {
    : String s ( string_from `abcdef` )
    ( nurl_print_int ( pick s @ ?i { T 3 } ) ) ( nurl_print `\n` )
    ^ 0
}
