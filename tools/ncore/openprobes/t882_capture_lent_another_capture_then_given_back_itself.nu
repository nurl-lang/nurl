// map: §7.4 | A2 | rejected | - | AGORA-882: `= o ( id other )  = o ( id o )` in the closure body, other replaced after the call
// main 525613db: faults under ASan (found by AGORA-873's finders).
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ( @ v ) f \ → v { = o ( id other ) = o ( id o ) }
    ( f )
    = other ( mk `a replacement value long enough for the heap` )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
