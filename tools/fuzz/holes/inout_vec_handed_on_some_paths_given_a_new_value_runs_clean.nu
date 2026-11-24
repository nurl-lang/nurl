// inout_vec_handed_on_some_paths_given_a_new_value_runs_clean: the guard for inout_vec_handed_on_some_paths_then_pushed_by_the_caller. The caller gives the argument a new value after the call, then pushes: accepted, and it runs clean.
// map: §7.6 | A2 | runs-clean | - | guard for h977: inout Vec maybe emptied by the callee, given a new value before use (AGORA-991)
$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ # i ( vec_len [i] v ) }

@ g3 inout ( Vec i ) p i c → i {
    ? == c 1 { ^ ( eat p ) } {}
    ^ 0
}

@ main → i {
    : ~ ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 1 )
    ( nurl_println_int ( g3 w 1 ) )
    = w ( vec_new [i] )
    ( vec_push [i] w 2 )
    ( nurl_println_int # i ( vec_len [i] w ) )
    ^ 0
}
