// map: §2.10 | A2 | rejected | - | AGORA-874: an owner that borrows another's payload grown through its own payload, a view of the other read
// main 3358873a: faults under ASan (found by AGORA-869's adversarial pass).
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ?String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    = o ( id other )
    ?? other { T so → {
            : s view ( string_data so )
            ?? o { T s → { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) } F → {} }
            ( nurl_println view )
        } F → {} }
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
