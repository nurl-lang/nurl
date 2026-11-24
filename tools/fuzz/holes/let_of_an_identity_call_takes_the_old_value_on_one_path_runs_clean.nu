// let_of_an_identity_call_takes_the_old_value_on_one_path_runs_clean: `: String k ( id s )`, `= s ( … )` in one arm only, then k and s read
// Closed: the binding codegen links to the owner by a `let` of a call that hands the owner back whole takes the old value over when the owner is given a new value (mem_udrop_hand_over, read by the walk as `pendho`): it owns it from then on, so the new value ends no borrow of it; on the other path k still borrows s, which is unchanged.
// main d39ded11f: refused ("'k' borrows from 's', which ended at … — it was given a new value"); --no-borrowck: runs clean under ASan/LSan.
// map: §7.6 | A2 | runs-clean | - | AGORA-1003: `: String k ( id s )`, `= s ( … )` in one arm only, then k and s read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id String p → String { ^ p }

@ main → i {
    : ~ String s ( string_from `a string long enough for the heap buffer here` )
    : String k ( id s )
    ? > ( nurl_str_len `ab` ) 1 { = s ( string_from `another string long enough for the heap buffer` ) } {}
    ( nurl_println ( string_data k ) )
    ( nurl_println ( string_data s ) )
    ^ 0
}
