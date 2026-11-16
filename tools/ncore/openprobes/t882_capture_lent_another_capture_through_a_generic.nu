// map: §7.4 | A2 | rejected | - | AGORA-882: through a generic identity, other replaced after the call
// main 525613db: faults under ASan (found by AGORA-872's skeptic).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ sid String a → String { ^ a }

@ vid ( Vec i ) a → ( Vec i ) { ^ a }

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String other ( mk `other value long enough for the heap here` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v { = o ( gid [? String] other ) }
    ( f )
    = other ( mk `replacement value long enough for the heap ok` )
    ( show o ) ( show other )
    ^ 0
}
