// vec_owner_given_another_by_name_takes_its_old_value_when_replaced_runs_clean: `= o other` of two `( Vec i )` owners, then `= other …` and an element of o read
// Control: the engine's hand-over to a reader codegen links stays (agora #881).
// main 22183195: runs clean (guard).
// map: §7.6 | A2 | runs-clean | - | AGORA-881: `= o other` of two `( Vec i )` owners, then `= other …` and an element of o read
$ `stdlib/core/string.nu`

@ id ( Vec i ) a → ( Vec i ) { ^ a }

@ main → i {
    : ~ ( Vec i ) other ( vec_new [i] )
    ( vec_push [i] other 1 ) ( vec_push [i] other 2 )
    : ~ ( Vec i ) o ( vec_new [i] )
    ( vec_push [i] o 7 )
    = o other
    = other ( vec_new [i] )
    ( vec_push [i] other 3 )
    ( nurl_println_int ( vec_at [i] o 1 ) )
    ^ 0
}
