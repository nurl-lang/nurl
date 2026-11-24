// closure_capture_handed_to_an_emptying_inout_given_a_new_value_runs_clean: the guard for closure_capture_handed_to_an_emptying_inout_then_pushed. The caller gives `w` a new value after running the closure, then pushes: accepted, and it runs clean.
// map: §2.11 | A2 | runs-clean | - | guard for h981: a closure's capture maybe emptied by its run, given a new value before use (AGORA-996)
$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ # i ( vec_len [i] v ) }

@ g3 inout ( Vec i ) p i c → i { ? == c 1 { ^ ( eat p ) } {} ^ 0 }

@ main → i {
    : ~ ( Vec i ) w ( vec_new [i] )
    : ( @ i ) f \ → i { ^ ( g3 w 1 ) }
    ( f )
    = w ( vec_new [i] )
    ( vec_push [i] w 2 )
    ^ - # i ( vec_len [i] w ) 1
}
