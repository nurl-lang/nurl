// map: §7.6 | A2 | rejected | - | AGORA-872: a closure local's lend given to a captured option owner, read after the closure returns
// main 3358873a: faults under ASan (found by AGORA-869's adversarial pass).
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String other ( mk `a closure local value long enough for heap` )
        = o ( id other )
    }
    ( f )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
