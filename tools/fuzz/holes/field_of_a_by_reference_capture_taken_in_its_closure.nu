// field_of_a_by_reference_capture_taken_in_its_closure: as h399, a mutable binding captured by reference: the field was
// released and not emptied in the binding.
// Closed: as h399 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h400 | as h399, captured by reference
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ main → i {
    : ~ Q q @ Q { ( mk ) ( mk ) }
    : ( @ v ) h \ → v { ( string_free . q name ) }
    ( h )
    ( nurl_println ( string_data . q tag ) )
    ^ 0
}
