// string_moved_by_assignment_freed_through_the_target_after_its_source_was_given_a_new_value_runs_clean: `= t a`, then `a` given a new string, then `( string_free t )`; `a` read after it.
// Closed (agora #634): `t` stayed a cursor over `a` after `= a …` had handed it a's old value, so freeing `t` cleared the drop flag of `a` too — of the new string, which nobody released (LeakSanitizer). `= t a` is a move now: `t` is no cursor over `a`, and freeing it frees what it owns.
// map: §2.2 | A2 | runs-clean | - | agora #634: a String moved by assignment, its source given a new value, the target freed: the source's new value leaked
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String a ( string_from `the first string, long enough for the heap, yes` )
    : ~ String t ( string_from `the third string, long enough for the heap, yes` )
    = t a
    = a ( string_from `a new string, long enough for the heap, yes yes` )
    ( string_free t )
    ( nurl_println ( string_data a ) )
    ^ 0
}
