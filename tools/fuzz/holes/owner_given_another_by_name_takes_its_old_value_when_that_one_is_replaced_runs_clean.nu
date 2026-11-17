// owner_given_another_by_name_takes_its_old_value_when_that_one_is_replaced_runs_clean: `= o other`, then `= other …` and o read: o is handed other's old value
// Control: the engine's hand-over to a reader codegen links stays (agora #881).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-881: `= o other`, then `= other …` and o read: o is handed other's old value
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o other
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
    ^ 0
}
