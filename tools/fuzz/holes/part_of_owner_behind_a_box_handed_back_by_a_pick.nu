// part_of_owner_behind_a_box_handed_back_by_a_pick: `= o ( npick o ( tail o ) k )`, a part of o behind a Box or o itself
// AGORA-875: refused - npick may hand back o itself or what tail lends (a part of o, named by no argument), and nurlc cannot tell which a run hands back (#412's rule; the call `( tail o )` lends on some runs). main 81530211: accepted, leak on the run that hands back the part
// map: §7.6 | A2 | rejected | - | AGORA-875: = o ( npick o ( tail o ) k ), a part of o behind a Box
// main 3358873a: faults under ASan (found by AGORA-869's adversarial pass).
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
    = o ( npick o ( tail o ) k )
    ( nshow o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
