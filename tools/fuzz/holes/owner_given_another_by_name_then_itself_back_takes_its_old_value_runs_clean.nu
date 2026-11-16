// owner_given_another_by_name_then_itself_back_takes_its_old_value_runs_clean: `= o other  = o ( id o )`, then `= other …` and o read: the by-name `=` linked o
// Control: the engine's hand-over to a reader codegen links, or a by-name move, stays (agora #886).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-886: `= o other  = o ( id o )`, then `= other …` and o read: the by-name `=` linked o
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o other
    = o ( id o )
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
    ^ 0
}
