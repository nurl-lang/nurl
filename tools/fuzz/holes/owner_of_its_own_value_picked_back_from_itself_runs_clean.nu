// owner_of_its_own_value_picked_back_from_itself_runs_clean: o owns its value, `= o ( pick o o k )`
// Control: `=`'s own binding handed to its call keeps refusing nothing where nothing it borrowed ends (agora #873).
// main 525613db: runs clean (guard).
// map: §2.10 | A2 | runs-clean | - | AGORA-873: o owns its value, `= o ( pick o o k )`
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ fwd ? String a → ?String { ^ ( id a ) }

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ? String third ( mk `a third value long enough for the heap` )
    = o ( pick o o k )
    = other ( mk `a replacement value long enough for the heap` )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
