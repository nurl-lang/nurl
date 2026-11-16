// map: §7.6 | A2 | rejected | - | AGORA-872: a closure local or the owner picked into a captured String owner
// main 3358873a: faults under ASan (found by AGORA-869's adversarial pass).
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ spick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ run i k → v {
    : ~ String o ( string_from `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : String other ( string_from `a closure local value long enough for heap` )
        = o ( spick o other k )
    }
    ( f )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
