// map: §7.4 | A2 | runs-clean | - | AGORA-961 guard: a binding of one call's lend of a closure local, assigned to a capture, still takes that local over without a copy
// AGORA-961: a cursor over one owner is moved, as before
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ sid String a → String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String a ( mk `closure a local long enough for heap ok` )
        : e ( id a )
        = o e
    }
    ( f )
    ( show o )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
