// owner_given_a_calls_lend_then_the_owner_by_name_takes_its_old_value_runs_clean: `= o ( id other )  = o other`, then `= other …` and o read
// Control: the engine's hand-over to a reader codegen links stays (agora #881).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-881: `= o ( id other )  = o other`, then `= other …` and o read
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    : i k ( nurl_str_len `x` )
    = o ( id other )
    = o other
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
    ^ 0
}
