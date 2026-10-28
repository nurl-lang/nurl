// H404: as h401, a closure over a nested field, the struct field holding it
// handed to a generic `sink`.
// Closed: as h401 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name }
: R { Q q i n }

@ take_any [T] sink T x → v {}

@ main → i {
    : R r @ R { @ Q { ( mk ) } 1 }
    : ( @ v ) g \ → v { ( nurl_println ( string_data . . r q name ) ) }
    ( take_any [Q] . r q )
    ( g )
    ^ 0
}
