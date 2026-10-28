// H391: as h389, through a binding read out of the parameter's field (`:
// String n . q name`) and handed whole to `string_free`.
// Closed: as h389 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name }

@ f Q q → v {
    : String n . q name
    ( string_free n )
}

@ main → i {
    : Q q @ Q { ( mk ) }
    ( f q )
    ( nurl_println ( string_data . q name ) )
    ^ 0
}
