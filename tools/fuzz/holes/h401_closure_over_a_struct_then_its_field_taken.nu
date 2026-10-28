// H401: a closure over a struct ran after a field of the struct was handed
// to `string_free`: the borrow sweep took the field hand-over for an element
// change, which a closure over the binding outlives.
// Closed: a field handed to a parameter that takes it ends what reached it,
// as a field replaced does (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
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
