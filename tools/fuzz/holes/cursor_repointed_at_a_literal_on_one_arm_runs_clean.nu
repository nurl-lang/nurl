// cursor_repointed_at_a_literal_on_one_arm_runs_clean: a cursor over a String's view re-pointed at a string literal on one arm; copy; fresh re-point; copy read.
// Kept: only a view binding that the walk has seen given a value that may be its own (a row marked `o`, an `@assign`) may own its value where paths meet (bck_may_own_some); one given only views and literals owns nothing, and re-pointing it frees nothing.
// main 4f15689: accepted; ran clean.
// map: StmtT.assign | A1 | runs-clean | - | a cursor re-pointed at a literal on one arm, copied, then given a fresh slice: the copy is read
$ `stdlib/core/string.nu`

@ pick String src b lit → i {
    : ~ s cur ( string_data src )
    ? lit { = cur `a literal string long enough to matter here` } {}
    : s nm cur
    = cur ( nurl_str_slice `zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz` 0 35 )
    ^ ( nurl_str_len nm )
}

@ main → i {
    : String s ( string_from `abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ` )
    ( nurl_print_int ( pick s T ) ) ( nurl_print `\n` )
    ^ 0
}
