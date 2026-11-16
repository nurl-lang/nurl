// binding_of_a_calls_lend_below_its_sources_replacement_in_a_loop_runs_clean: in a loop, `= other …`, then `: String o ( id other )` read
// Control: the engine's hand-over to a reader codegen links, or a by-name move, stays (agora #886).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-886: in a loop, `= other …`, then `: String o ( id other )` read
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ i k 0
    ~ < k 3 {
        = other ( string_from `cccccccccccccccccccccccccccccc` )
        : String o ( id other )
        ( nurl_println ( string_data o ) )
        = k + k 1
    }
    ^ 0
}
