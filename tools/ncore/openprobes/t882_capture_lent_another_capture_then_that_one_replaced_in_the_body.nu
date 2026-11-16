// map: §7.4 | A2 | rejected | - | AGORA-882: `= a ( id b )  = b ( mk … )` both inside the closure body
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
    : ~ ? String a ( mk `value a long enough for the heap here ok` )
    : ~ ? String b ( mk `value b long enough for the heap here ok` )
    : ~ ( @ v ) f \ → v { = a ( id b ) = b ( mk `fresh b long enough for the heap here ok` ) }
    ( f )
    ( show a ) ( show b )
    ^ 0
}
