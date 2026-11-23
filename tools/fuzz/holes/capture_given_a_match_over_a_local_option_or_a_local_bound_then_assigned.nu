// map: §7.4 | A2 | runs-clean | - | AGORA-953 (from CodeRabbit on github#2205): `: String e ?? o { T s → s F → ( id a ) }  = cap e` in a closure, o a local ?String and a a local String: the binding's owners are of different types, so none is keyed; cap gets a value of its own
// Was a heap-use-after-free under ASan on main c4c0f35.
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ run i k → v {
    : ~ String cap ( string_from `outer value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : ?String o ? == k 0 @ ?String { T ( string_from `option payload long enough for heap ok` ) } @ ?String { F }
        : String a ( string_from `plain local long enough for the heap ok` )
        : String e ?? o { T s → s F → ( id a ) }
        = cap e
    }
    ( f )
    ( nurl_println ( string_data cap ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
