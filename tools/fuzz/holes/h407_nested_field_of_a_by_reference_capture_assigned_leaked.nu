// H407: as h405, a nested field (`= . . r q tag`).
// Closed: as h405 (agora #144).
// v0.80.0: accepted; LeakSanitizer reported memory leaks.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }
: R { Q q i n }

@ main → i {
    : ~ R r @ R { @ Q { ( mk ) ( mk ) } 1 }
    : ( @ v ) h \ → v { = . . r q tag ( mk ) }
    ( h )
    ( nurl_println ( string_data . . r q tag ) )
    ^ 0
}
