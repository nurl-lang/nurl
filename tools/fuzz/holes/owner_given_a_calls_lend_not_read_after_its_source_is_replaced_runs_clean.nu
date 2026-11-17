// owner_given_a_calls_lend_not_read_after_its_source_is_replaced_runs_clean: `= o ( id other )  = other …`, o not read again
// Control: the engine's hand-over to a reader codegen links stays (agora #881).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-881: `= o ( id other )  = other …`, o not read again
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    : i k ( nurl_str_len `x` )
    = o ( id other )
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ^ 0
}
