// map: §7.4 | A2 | runs-clean | - | AGORA-961: a `:` join binding that may lend the capture itself or a closure local, assigned to that capture, is copied in before the old value goes
// AGORA-961 (closed): main 07e02a7 heap-use-after-free under ASan
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ sid String a → String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String a ( mk `closure a local long enough for heap ok` )
        : e ? == k 0 ( id o ) ( id a )
        = o e
    }
    ( f )
    ( show o )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
