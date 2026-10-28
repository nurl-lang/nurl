// H403: a view into a nested field (`string_data . . r q name`) read after
// the struct field holding it (`. r q`) was handed to a generic `sink`.
// Closed: as h401 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name }
: R { Q q i n }

@ take_any [T] sink T x → v {}

@ main → i {
    : R r @ R { @ Q { ( mk ) } 1 }
    : s v ( string_data . . r q name )
    ( take_any [Q] . r q )
    ( nurl_println v )
    ^ 0
}
