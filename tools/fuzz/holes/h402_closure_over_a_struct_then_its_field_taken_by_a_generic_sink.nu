// H402: as h401, the field handed to a generic `sink`.
// Closed: as h401 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name }

@ take_any [T] sink T x → v {}

@ main → i {
    : Q q @ Q { ( mk ) }
    : ( @ v ) g \ → v { ( nurl_println ( string_data . q name ) ) }
    ( take_any [String] . q name )
    ( g )
    ^ 0
}
