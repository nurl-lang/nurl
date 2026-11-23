// map: §7.4 | A2 | runs-clean | - | AGORA-961 (AGORA-242's twin): a join of two closure locals' lends bound by `:`, then assigned to a capture by name, is copied in
// AGORA-961 (closed): main 07e02a7 leaked (LSan); twin of tools/fuzz/holes/capture_lent_a_closure_local_through_a_join_runs_clean.nu
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ sid String a → String { ^ a }

@ vid ( Vec i ) a → ( Vec i ) { ^ a }

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String a ( mk `closure a local long enough for heap ok` )
        : ?String b ( mk `closure b local long enough for heap ok` )
        : __el ? == k 0 ( id a ) ( id b )
        = o __el
    }
    ( f )
    ( show o )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
