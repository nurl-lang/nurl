// closure_over_a_struct_then_its_field_taken_by_a_generic_sink: as h401, the field handed to a generic `sink`.
// Closed: as h401 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h402 | as h401, a generic sink
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
