// map: §7.4 | A2 | rejected | - | agora #967: `: String e ? == k 0 ( ex a ) ( ex b )  = o e` in a closure, ex lending a field of a closure-local struct: o takes over both whole owners and releases only the field
// A leak under LSan on main c4c0f35 (AGORA-967).
$ `stdlib/core/string.nu`

: P { String name String extra }

@ mk s t → P { ^ @ P { ( string_from t ) ( string_from ( nurl_str_cat t ` extra` ) ) } }

@ ex P p → String { ^ . p extra }

@ run i k → v {
    : ~ String o ( string_from `outer value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : P a ( mk `closure a local long enough for heap ok` )
        : P b ( mk `closure b local long enough for heap ok` )
        : String e ? == k 0 ( ex a ) ( ex b )
        = o e
    }
    ( f )
    ( nurl_println ( string_data o ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
