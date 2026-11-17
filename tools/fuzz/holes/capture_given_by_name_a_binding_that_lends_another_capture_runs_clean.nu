// capture_given_by_name_a_binding_that_lends_another_capture_runs_clean: `: ?String x ( id other2 )  = o x` in a closure, other2 replaced after the call, o read
// AGORA-904: accepted - o is given its own copy where x does not own its value (main 05206020: accepted with o a lend of other2, heap-use-after-free)
// map: §7.4 | A2 | runs-clean | - | AGORA-904: `: ?String x ( id other2 )  = o x` in a closure, other2 replaced after the call, o read
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other2 ( mk `a second outer value long enough for heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String loc ( mk `a closure local value long enough for heap` )
        : ?String x ( id other2 )
        = o x
    }
    ( f )
    = other2 ( mk `a replacement value long enough for the heap` )
    ( show o )
}

@ main → i { ( run 0 ) ^ 0 }
