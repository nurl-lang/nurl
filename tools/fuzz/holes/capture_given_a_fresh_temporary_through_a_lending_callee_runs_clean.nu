// capture_given_a_fresh_temporary_through_a_lending_callee_runs_clean: `= o ( rid ( rnew … ) )` of a `% Drop` struct: a temporary handed through, not a lend to copy
// Closed: a capture by pointer given a lend of what dies with the closure (a local or a parameter of it) is given a copy it owns, as an `inout` parameter is (gen_assign; agora #872).
// main 525613db: runs clean (guard).
// map: §7.4 | A2 | runs-clean | - | AGORA-872: `= o ( rid ( rnew … ) )` of a `% Drop` struct: a temporary handed through, not a lend to copy
$ `stdlib/core/string.nu`

: R { String s }

% Drop R { @ drop R r → v { ( nurl_println `released` ) } }

@ rid R a → R { ^ a }

@ rnew s t → R { ^ @ R { ( string_from t ) } }

@ main → i {
    : ~ R o ( rnew `outer value long enough for the heap here` )
    : ~ ( @ v ) f \ → v { = o ( rid ( rnew `a fresh value long enough for the heap ok` ) ) }
    ( f )
    ( nurl_println ( string_data . o s ) )
    ^ 0
}
