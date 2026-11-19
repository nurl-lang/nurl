// part_of_owner_behind_a_box_handed_back_by_a_forwarder_runs_clean: `= o ( forward o )`, forward handing back `( tail o )`
// AGORA-907 (CodeRabbit on github#1938): accepted - a function handing back such a call hands on what it does (retaggl), and the part copy is made once
// map: §7.6 | A2 | runs-clean | - | AGORA-907
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

@ forward ? N o → ?N { ^ ( tail o ) }

@ nshow ? N o → v { ?? o { T n → { ( nurl_println ( string_data . n s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : N inner @ N { ( string_from `the inner node string long enough for the heap` ) @ ?( Box N ) { F } }
    : ~ ? N o @ ?N { T @ N { ( string_from `the outer node string long enough for the heap` ) @ ?( Box N ) { T ( box_new [N] inner ) } } }
    = o ( forward o )
    ( nshow o )
}

@ main → i {
    ( run 1 )
    ^ 0
}
