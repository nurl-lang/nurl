// map: §7.4 | A2 | runs-clean | - | AGORA-961: a `??` of two closure locals' lends bound by `:`, assigned to a capture
// AGORA-961 (closed): main 07e02a7 leaked (LSan)
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ sid String a → String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String a ( mk `closure a local long enough for heap ok` )
        : ?String b ( mk `closure b local long enough for heap ok` )
        : e ?? ( mk `x` ) { T s → ( id a ) F → ( id b ) }
        = o e
    }
    ( f )
    ( show o )
}

@ main → i { ( run 0 ) ^ 0 }
