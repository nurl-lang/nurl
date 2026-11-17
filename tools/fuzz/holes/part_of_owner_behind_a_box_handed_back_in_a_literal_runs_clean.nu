// part_of_owner_behind_a_box_handed_back_in_a_literal_runs_clean: `= o ( tail o )`, tail handing back `@ ?N { T ( box_get [N] b ) }` of o's own Box field
// AGORA-906: accepted - on the runs tail lends, o is given its own copy of the node, and its old value goes (main 81530211: heap-use-after-free, the old value released under the node)
// map: §7.6 | A2 | runs-clean | - | AGORA-906: a part of the owner behind a Box, handed back in a literal
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

$ `stdlib/core/box.nu`

: N { String s ? ( Box N ) next }

@ npick ? N a ? N b i k → ?N { ? == k 0 { ^ a } { ^ b } }

@ tail ? N o → ?N {
    ?? o { T n → { ?? . n next { T b → { ^ @ ?N { T ( box_get [N] b ) } } F → {} } } F → {} }
    ^ @ ?N { F }
}

@ nshow ? N o → v { ?? o { T n → { ( nurl_println ( string_data . n s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : N inner @ N { ( string_from `the inner node string long enough for the heap` ) @ ?( Box N ) { F } }
    : ~ ? N o @ ?N { T @ N { ( string_from `the outer node string long enough for the heap` ) @ ?( Box N ) { T ( box_new [N] inner ) } } }
    = o ( tail o )
    ( nshow o )
}

@ main → i {
    ( run 1 )
    ^ 0
}
