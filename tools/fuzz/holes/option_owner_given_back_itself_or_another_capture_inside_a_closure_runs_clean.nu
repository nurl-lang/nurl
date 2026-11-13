// option_owner_given_back_itself_or_another_capture_inside_a_closure_runs_clean: `= o ( id o )` and `= o ( id other )` inside closures run twice.
// Guard for agora #378: o's own value handed back through a capture is kept by its key; another capture's lend replaces it.
// map: §7.6 | A2 | runs-clean | - | agora #378 guard: an owner given back itself or another capture inside a closure
$ `stdlib/core/string.nu`

@ id ? String x → ?String { ^ x }

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owner string, long enough for the heap allocation` ) }
    : ?String other @ ?String { T ( string_from `the other string, long enough for the heap allocation` ) }
    : ~ ( @ v ) f \ → v { = o ( id o ) }
    ( f ) ( f )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    : ~ ( @ v ) g \ → v { = o ( id other ) }
    ( g ) ( g )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
