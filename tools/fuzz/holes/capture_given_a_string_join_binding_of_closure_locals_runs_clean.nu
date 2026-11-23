// map: §7.4 | A2 | runs-clean | - | AGORA-953 (found in AGORA-961): a String join of two closure locals bound by `:`, assigned to a capture
// AGORA-953 (closed by its `__jalias` move): main 07e02a7 leaked (LSan)
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ sid String a → String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ String o ( string_from `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : String a ( string_from `closure a local long enough for heap ok` )
        : String b ( string_from `closure b local long enough for heap ok` )
        : e ? == k 0 ( sid a ) ( sid b )
        = o e
    }
    ( f )
    ( nurl_println ( string_data o ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
