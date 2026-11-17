// owner_given_another_by_name_on_one_arm_and_a_fresh_value_on_the_other_takes_its_old_value_runs_clean: `? c { = o other } { = o ( mk ) }`, then `= other …` and o read
// Control: a by-name link on one arm keeps the engine's hand-over (agora #886).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-886: `? c { = o other } { = o ( mk ) }`, then `= other …` and o read
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    : i k ( nurl_str_len `x` )
    ? == k 1 { = o other } { = o ( string_from `dddddddddddddddddddddddddddddddd` ) }
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
    ^ 0
}
