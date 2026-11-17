// owner_given_another_by_name_below_its_replacement_in_a_loop_runs_clean: in a loop, `= other …`, o read, then `= o other` below it
// Control: the engine's hand-over to a reader codegen links, or a by-name move, stays (agora #886).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-886: in a loop, `= other …`, o read, then `= o other` below it
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    : ~ i k 0
    ~ < k 3 {
        = other ( string_from `cccccccccccccccccccccccccccccc` )
        ( nurl_println ( string_data o ) )
        = o other
        = k + k 1
    }
    ^ 0
}
