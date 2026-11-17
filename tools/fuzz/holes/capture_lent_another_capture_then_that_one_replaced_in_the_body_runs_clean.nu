// map: §7.4 | A2 | runs-clean | - | AGORA-882: `= a ( id b )  = b ( mk … )` both inside the closure body - closed by AGORA-904: the capture is given its own copy
// AGORA-882, closed by AGORA-904: the by-pointer capture is given its own copy of what the call lends (the caller's frame cannot follow a lend of another capture); main 05206020: heap-use-after-free
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
