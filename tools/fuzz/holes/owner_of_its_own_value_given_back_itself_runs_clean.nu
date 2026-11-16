// owner_of_its_own_value_given_back_itself_runs_clean: o owns its value, `= o ( id o )`, then another binding replaced and o read
// Control: `=`'s own binding handed to its call keeps refusing nothing where nothing it borrowed ends (agora #873).
// main 525613db: runs clean (guard).
// map: §2.10 | A2 | runs-clean | - | AGORA-873: o owns its value, `= o ( id o )`, then another binding replaced and o read
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    = o ( id o )
    = other ( mk `a replacement value long enough for the heap` )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
