// let_of_an_identity_call_of_a_vec_takes_the_old_value_runs_clean: `: ( Vec i ) k ( idv v )  = v ( … )`, then k read
// Closed: the binding codegen links to the owner by a `let` of a call that hands the owner back whole takes the old value over when the owner is given a new value (mem_udrop_hand_over, read by the walk as `pendho`): it owns it from then on, so the new value ends no borrow of it; a `Vec` as a `String`.
// main d39ded11f: refused ("'k' borrows from 's', which ended at … — it was given a new value"); --no-borrowck: runs clean under ASan/LSan.
// map: §7.6 | A2 | runs-clean | - | AGORA-1003: `: ( Vec i ) k ( idv v )  = v ( … )`, then k read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ idv ( Vec i ) p → ( Vec i ) { ^ p }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 ) ( vec_push [i] v 2 )
    : ( Vec i ) k ( idv v )
    = v ( vec_new [i] )
    ( vec_push [i] v 9 )
    ( nurl_println_int ( vec_len [i] k ) )
    ^ 0
}
