// owner_or_its_part_behind_a_box_handed_back_by_a_callee_defined_below_runs_clean: as owner_or_its_part_behind_a_box_handed_back_runs_clean, choose defined below its caller
// AGORA-907: accepted (main e7133a6c: a leak)
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

@ nshow ? N o → v { ?? o { T n → { ( nurl_println ( string_data . n s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : N inner @ N { ( string_from `the inner node string long enough for the heap` ) @ ?( Box N ) { F } }
    : ~ ? N o @ ?N { T @ N { ( string_from `the outer node string long enough for the heap` ) @ ?( Box N ) { T ( box_new [N] inner ) } } }
    = o ( choose o k )
    ( nshow o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}

@ choose ? N o i k → ?N {
    ? == k 0 { ^ o } {}
    ?? o { T n → { ?? . n next { T b → { ^ @ ?N { T ( box_get [N] b ) } } F → {} } } F → {} }
    ^ @ ?N { F }
}
