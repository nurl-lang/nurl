// option_owner_given_a_lend_out_of_a_capture_inside_a_closure_runs_clean: `\ → v { = o ( first vs ) }` with `o` and `vs` captured and `first` handing back `( vec_get vs 0 )`, a forwarder defined above the closure.
// Closed (agora #378): the closure cannot tell whether the captured `vs` holds o's own value, so o's old value was kept back on every run (a leak). Where the type keys, the assignment now asks by key at run time (`__ud_unk_lend`): o keeps a value that is its own, and the old value goes otherwise.
// map: §7.6 | A2 | runs-clean | - | agora #378: an option owner given a lend out of a capture inside a closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec String ) vs → ?String { ^ ( vec_get [String] vs 0 ) }

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string, long enough for the heap allocation` ) )
    : ~ ? String o @ ?String { T ( string_from `the owner string, long enough for the heap allocation` ) }
    : ~ ( @ v ) f \ → v { = o ( first vs ) }
    ( f )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
