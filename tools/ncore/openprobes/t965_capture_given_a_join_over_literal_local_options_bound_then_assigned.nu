// map: §7.4 | A2 | rejected | - | agora #965: `: ?String e ? == k 0 ( idq a ) ( idq b )  = cap e` in a closure, a and b literal-built local options: cap holds what a or b releases
// Heap-use-after-free under ASan on main 3cf624c (AGORA-965).
$ `stdlib/core/string.nu`

@ idq ? String a → ?String { ^ a }

@ run i k → v {
    : ~ ? String cap @ ?String { T ( string_from `outer value long enough for the heap here` ) }
    : ~ ( @ v ) f \ → v {
        : ?String a @ ?String { T ( string_from `option a long enough for the heap ok ok` ) }
        : ?String b @ ?String { T ( string_from `option b long enough for the heap ok ok` ) }
        : ?String e ? == k 0 ( idq a ) ( idq b )
        = cap e
    }
    ( f )
    ?? cap { T s → ( nurl_println ( string_data s ) ) F → {} }
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
