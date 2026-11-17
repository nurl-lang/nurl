// option_owner_given_another_by_name_takes_its_old_value_when_replaced_runs_clean: `= o other` of two `?String` owners, then `= other …` and o's payload read
// Control: the engine's hand-over to a reader codegen links stays (agora #881).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-881: `= o other` of two `?String` owners, then `= other …` and o's payload read
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ mk s s → ?String { ^ @ ?String { T ( string_from s ) } }

@ main → i {
    : ~ ? String other ( mk `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ ? String o ( mk `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o other
    = other ( mk `cccccccccccccccccccccccccccccc` )
    ?? o { T q → { ( nurl_println ( string_data q ) ) } F → {} }
    ^ 0
}
