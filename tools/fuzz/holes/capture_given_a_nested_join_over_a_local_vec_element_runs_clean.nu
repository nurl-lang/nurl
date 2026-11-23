// map: §7.4 | A2 | runs-clean | - | AGORA-964: a `:` binding of `? k ?? ( vec_get [String] w 0 ) { T s → s … } ( id a )`, w a closure-local Vec, assigned to a capture, is copied in
// AGORA-964 (closed): main 502c1b08 heap-use-after-free under ASan; the join cursor names only `a`, so a takeover left the capture claiming w's element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id String a → String { ^ a }

@ mko → ?String { ^ @ ?String { T ( string_from `a fresh option payload long enough for heap` ) } }

@ run b k → v {
    : ~ String o ( string_from `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ( Vec String ) w ( vec_new [String] )
        ( vec_push [String] w ( string_from `element long enough for a heap buffer` ) )
        : String a ( string_from `closure a local long enough for heap ok` )
        : e ? k ?? ( vec_get [String] w 0 ) { T s → s F → ( id a ) } ( id a )
        = o e
    }
    ( f )
    ( nurl_println ( string_data o ) )
}

@ main → i { ( run T ) ( run F ) ^ 0 }
