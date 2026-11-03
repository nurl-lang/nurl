// cursor_repointed_at_views_only_runs_clean: `cur` is re-pointed only at views of Strings that outlive the loop, never given a value of its own: re-pointing it frees nothing, so a copy taken before is read after.
// Closed: a binding that is a borrow on one path into a merge and its own value on another (a cursor a loop re-points at a fresh slice, a `?` / `??` arm that gives it one) joins to BCK_MAYBE_OWNED, not to a plain borrow: re-pointing it releases what it owned there, so what was borrowed from it ends (bck_borrow_sweep), and a copy of it borrows it as well as what it borrows (bck_sx_name, bck_borrow_owners).
// main 4f15689: accepted; ran clean.
// map: StmtT.assign | A1 | runs-clean | - | a cursor that only ever views (two Strings it alternates between): a copy outlives a re-point
$ `stdlib/core/string.nu`

@ rows String a String b → i {
    : ~ s cur ( string_data a )
    : ~ i n 0
    : ~ i k 0
    ~ < k 3 {
        : s nm cur
        = cur ? == 0 % k 2 ( string_data b ) ( string_data a )
        = n + n ( nurl_str_len nm )
        = k + k 1
    }
    ^ n
}

@ main → i {
    : String a ( string_from `abc` )
    : String b ( string_from `de` )
    ( nurl_print_int ( rows a b ) ) ( nurl_print `\n` )
    ^ 0
}
