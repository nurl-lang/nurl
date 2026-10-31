// nested_field_of_a_parameter_taken_then_read: as h389, a nested struct field of the parameter (`. r q`) handed to
// a generic `sink`.
// Closed: as h389 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: CallT.sink | A1 | rejected | h390 | as h389, a nested struct field handed to a generic sink
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name }
: R { Q q i n }

@ take_any [T] sink T x → v {}

@ f R r → v { ( take_any [Q] . r q ) }

@ main → i {
    : R r @ R { @ Q { ( mk ) } 1 }
    ( f r )
    ( nurl_println ( string_data . . r q name ) )
    ^ 0
}
