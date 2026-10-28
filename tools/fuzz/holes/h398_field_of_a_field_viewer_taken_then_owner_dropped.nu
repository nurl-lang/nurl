// H398: a field of a binding read out of a struct field (`: Q e . r q`, then
// `( string_free . e name )`): only the viewer's copy was emptied, and the
// owner released the field again.
// Closed: as h394 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name }
: R { Q q i n }

@ main → i {
    : R r @ R { @ Q { ( mk ) } 1 }
    : Q e . r q
    ( string_free . e name )
    ^ 0
}
