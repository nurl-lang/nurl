// owner_given_a_capture_by_name_takes_its_old_value_when_the_closure_replaces_it_runs_clean: in a closure, `= o p` of a captured `: ~ String`, then `= p …` and o read
// Control: a by-pointer capture's replacement still hands its old value to the reader it linked (agora #886).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-886: in a closure, `= o p` of a captured `: ~ String`, then `= p …` and o read
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String p ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ( @ v ) f \ → v {
        : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
        = o p
        = p ( string_from `cccccccccccccccccccccccccccccc` )
        ( nurl_println ( string_data o ) )
    }
    ( f )
    ( nurl_println ( string_data p ) )
    ^ 0
}
