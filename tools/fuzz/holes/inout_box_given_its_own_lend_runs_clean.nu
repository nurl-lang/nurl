// inout_box_given_its_own_lend_runs_clean: agora #456 guard — `= o ( idbox o )` over an `inout ( Box String )`
// Guard: a Box given back its own value keeps it (same key): no copy, no release.
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #456 guard: `= o ( idbox o )` over an inout Box
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

@ idbox ( Box String ) b → ( Box String ) { ^ b }

@ put inout ( Box String ) o → v { = o ( idbox o ) }

@ main → i {
    : ~ ( Box String ) a ( box_new [String] ( string_from `a fresh string long enough for the heap, one` ) )
    ( put a )
    ( nurl_println ( string_data ( box_get [String] a ) ) )
    ^ 0
}
