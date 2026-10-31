// closure_over_a_struct_then_its_field_taken: a closure over a struct ran after a field of the struct was handed
// to `string_free`: the borrow sweep took the field hand-over for an element
// change, which a closure over the binding outlives.
// Closed: a field handed to a parameter that takes it ends what reached it,
// as a field replaced does (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h401 | a closure over a struct ran after its field was handed to string_free (UAF): a field hand-over to a sink ends the views of the struct, as a field replaced does
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name }

@ main → i {
    : Q q @ Q { ( mk ) }
    : ( @ v ) g \ → v { ( nurl_println ( string_data . q name ) ) }
    ( string_free . q name )
    ( g )
    ^ 0
}
